# MLOps

MLOps experiments, starting with GitHub Actions workflows.

## Workflows

All workflows live in [`.github/workflows/`](.github/workflows/).

| Workflow | File | Trigger | What it does |
| --- | --- | --- | --- |
| Build | `build.yml` | Push / PR to `main` or `master`, manual | Checks out the code, sets up Python 3.11, installs `requirements.txt`, builds the package (or compiles sources), and runs `pytest` if `tests/` exists |
| Trigger | `trigger.yml` | Manual | Starts the Downstream workflow via `gh workflow run`, passing an environment input |
| Downstream | `downstream.yml` | Manual or from Trigger | Prints the inputs it received; placeholder for real work such as a deploy |
| AWS S3 List | `aws-s3-ls.yml` | Manual | Gets temporary AWS credentials from STS via OIDC and runs `aws s3 ls` |
| SageMaker Pipeline | `sagemaker-pipeline.yml` | Push to `master` touching `pipeline/`, manual | Creates or updates the SageMaker pipeline in [`pipeline/`](pipeline/) (preprocess → train XGBoost → register model) and runs it. Needs `SAGEMAKER_ROLE_ARN` and `SAGEMAKER_BUCKET` repo variables |
| Claude CI/CD Integration | `claude_cicd_integration.yml` | After a successful Build on `master` | Runs Claude Code via `anthropics/claude-code-action`, which uses the `run-workflows` skill to run AWS S3 List. Needs an `ANTHROPIC_API_KEY` repo secret |

Run the manual workflows from **Actions → *workflow name* → Run workflow**.

## Claude Code skills

Project skills for [Claude Code](https://claude.com/claude-code) live in [`.claude/skills/`](.claude/skills/), one folder per skill with a `SKILL.md`.

| Skill | What it does |
| --- | --- |
| `add-workflow` | Adds a new GitHub Actions workflow following this repo's conventions |
| `run-workflows` | Runs several workflows one after another, waiting for each to finish and stopping at the first failure |

`run-workflows` needs the GitHub CLI (`brew install gh && gh auth login`). Its script can also be run directly:

```bash
.claude/skills/run-workflows/run_sequence.sh [--ref <branch>] <workflow>[:key=value,...] ...

# Example: build, list S3, then run Downstream for staging
.claude/skills/run-workflows/run_sequence.sh build.yml aws-s3-ls.yml downstream.yml:environment=staging
```

## Kubernetes

Helm charts live in [`kubernetes/`](kubernetes/).

| Chart | What it installs |
| --- | --- |
| `prometheus` | Prometheus server (`prom/prometheus`) with RBAC for Kubernetes service discovery, a PVC for TSDB data, and scrape jobs for the API server, nodes, cAdvisor, and pods annotated `prometheus.io/scrape: "true"` |

```bash
helm install prometheus kubernetes/prometheus -n monitoring --create-namespace
kubectl -n monitoring port-forward svc/prometheus 9090:9090   # http://localhost:9090
```

Override settings in `values.yaml` with `--set` or `-f`, e.g. `--set persistence.enabled=false` or `--set retention=30d`. Scrape jobs and alert rules are under `config` and `rules`.

Plain manifests for an API live in [`kubernetes/api/`](kubernetes/api/): a Deployment (probes, resource limits, Prometheus scrape annotations), a ClusterIP Service on port 80, an HPA (2–10 replicas at 70% CPU), and a VPA that adjusts memory requests only so it doesn't conflict with the HPA. The image is a placeholder (`hashicorp/http-echo`); swap in your own and adjust the container port.

```bash
kubectl apply -k kubernetes/api
```

The HPA needs metrics-server (`minikube addons enable metrics-server`). The VPA needs the [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) installed; without it, `kubectl apply` fails on `vpa.yaml`.

[`kubernetes/secret-rotation/`](kubernetes/secret-rotation/) is a Helm chart that keeps Kubernetes Secrets in sync with AWS Secrets Manager using the [External Secrets Operator](https://external-secrets.io/) (ESO). Rotate a secret in Secrets Manager and ESO writes the new value into the Kubernetes Secret within `refreshInterval` (default 1h). It can also generate in-cluster passwords that ESO replaces every `rotateEvery`, for values only the cluster uses, such as session signing keys. List secrets under `secrets` and `generated` in `values.yaml`.

Install ESO first. The Terraform in [`aws/`](aws/) already gives its service account (`external-secrets/external-secrets`) read access to Secrets Manager secrets named `mlops/*` through EKS Pod Identity; set `store.serviceAccount` only if you use IRSA instead. Then install the chart in each cluster with that cluster's region:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
helm install secret-rotation kubernetes/secret-rotation -n default --set region=us-east-1 -f my-secrets.yaml
kubectl get externalsecrets
```

Pods that read secrets as environment variables keep the old value until they restart; [Stakater Reloader](https://github.com/stakater/Reloader) with the `reloader.stakater.com/auto: "true"` annotation restarts them on each rotation.

[`kubernetes/configmaps/`](kubernetes/configmaps/) is a Helm chart that creates ConfigMaps listed under `configMaps` in `values.yaml`, from key/value pairs (`data`; numbers and booleans are quoted for you), from files bundled in the chart (`files: files/api/*`, one key per file name), or both. Each entry can set `labels`, `annotations`, and `immutable`. Put files in a `files/` folder inside the chart. [`examples/etcd.yaml`](kubernetes/configmaps/examples/etcd.yaml) is a complete sample: the shared `ETCD_*` settings for a 3-member etcd StatefulSet, with the per-member env vars the pods add. Like Secrets, ConfigMaps read as environment variables only take effect after a pod restart; the Reloader annotation `reloader.stakater.com/auto: "true"` on a Deployment handles that.

```bash
helm install configmaps kubernetes/configmaps -n default -f my-configmaps.yaml
```

[`kubernetes/vault/`](kubernetes/vault/) is a Helm chart that installs [HashiCorp Vault](https://developer.hashicorp.com/vault) (upstream chart `hashicorp/vault` 0.34.1, Vault 2.0.4) as a 3-pod HA cluster with integrated Raft storage, one pod per AZ, auto-unsealed by the AWS KMS key and IAM role from [`aws/`](aws/). The sidecar injector is off; apps get Vault secrets through the External Secrets Operator. Set the region and key alias per cluster:

```bash
helm dependency build kubernetes/vault
helm install vault kubernetes/vault -n vault --create-namespace \
  --set global.awsKms.region=us-east-1 \
  --set global.awsKms.keyId=alias/vault-unseal-mlops-us-east-1
kubectl -n vault exec -it vault-0 -- vault operator init   # prints recovery keys and a root token; store them safely
```

The other pods join through `retry_join` and every pod unseals itself with KMS on start. Vault serves plain HTTP inside the cluster; configure TLS in the listener before production use.

[`kubernetes/istio/`](kubernetes/istio/) installs the [Istio](https://istio.io/) service mesh (1.30.6) as three Helm charts wrapping the upstream ones. They must be installed in order, as separate releases, because istiod needs Istio's CRDs and the gateway pods need istiod's injection webhook to be running:

| Chart | What it installs |
| --- | --- |
| `base` | Istio CRDs and cluster-wide resources |
| `istiod` | Control plane, 2–5 replicas spread across AZs, access logs, Prometheus metrics merging, and a mesh-wide `PeerAuthentication` (`mtls.mode`, default `PERMISSIVE`; switch to `STRICT` once every client has a sidecar). `global.meshID`, `global.multiCluster.clusterName`, and `global.network` identify the cluster for a future multi-cluster mesh |
| `gateway` | Ingress gateway (`istio: ingressgateway`) behind an internet-facing AWS NLB, 2–10 replicas spread across AZs |

```bash
for c in base istiod gateway; do helm dependency build kubernetes/istio/$c; done
helm install istio-base kubernetes/istio/base -n istio-system --create-namespace --wait
helm install istiod kubernetes/istio/istiod -n istio-system --wait \
  --set istiod.global.multiCluster.clusterName=mlops-us-east-1 \
  --set istiod.global.network=mlops-us-east-1
helm install istio-ingress kubernetes/istio/gateway -n istio-ingress --create-namespace --wait
```

[`examples/api-routing.yaml`](kubernetes/istio/examples/api-routing.yaml) routes traffic from the gateway to the API in `kubernetes/api/`, with a timeout and retries; label the namespace `istio-injection=enabled` and restart the API so its pods get sidecars.

[`kubernetes/gpu/`](kubernetes/gpu/) runs workloads on NVIDIA GPUs. GPU nodes come from the `gpu` Karpenter pool in [`kubernetes/karpenter/`](kubernetes/karpenter/) (g5/g6/g6e, tainted `nvidia.com/gpu`, at most 16 GPUs, removed after 5 idle minutes), which boots the EKS NVIDIA AMI with the driver and container toolkit preinstalled.

| Chart | What it does |
| --- | --- |
| `operator` | NVIDIA GPU Operator v26.7.2 with the driver and toolkit turned off (the AMI has them): device plugin so pods can request `nvidia.com/gpu`, GPU feature discovery labels (`nvidia.com/gpu.product`, ...), and the DCGM exporter, scraped by the `nvidia-dcgm-exporter` job in [`kubernetes/prometheus/`](kubernetes/prometheus/). Optional GPU time-slicing is commented in `values.yaml` |
| `workload` | Runs one container on GPUs as a `Job` (training, batch) or a `Deployment` plus Service (inference). Sets the GPU limit, the GPU toleration, a memory-backed `/dev/shm` for PyTorch and NCCL, and for Jobs `karpenter.sh/do-not-disrupt` so Karpenter doesn't move a running job. Defaults to NVIDIA's CUDA vector-add sample as a smoke test |

```bash
helm dependency build kubernetes/gpu/operator
helm install gpu-operator kubernetes/gpu/operator -n gpu-operator --create-namespace --wait

# Smoke test: launches a GPU node, prints "Test PASSED"
helm install gpu-smoke kubernetes/gpu/workload
kubectl logs job/gpu-smoke-gpu-workload -f

# An inference server on 1 GPU
helm install llm kubernetes/gpu/workload --set kind=Deployment \
  --set image.repository=vllm/vllm-openai --set image.tag=<version> \
  --set 'args={--model,Qwen/Qwen2.5-1.5B-Instruct}'
```

[`kubernetes/karpenter/`](kubernetes/karpenter/) adds node autoscaling on EKS with [Karpenter](https://karpenter.sh/): a default `NodePool` (spot and on-demand c/m/r instances, gen 5+, capped at 100 CPU / 400Gi, consolidates empty or underused nodes) and an `EC2NodeClass` (AL2023 AMI, IMDSv2, subnets and security groups found by the `karpenter.sh/discovery` tag). When the API's HPA adds pods that don't fit, Karpenter launches nodes for them.

Karpenter itself must be installed first, including its IAM roles, interruption queue, and discovery tags; follow the [Getting Started guide](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/). Then apply the manifests with your cluster name filled in:

```bash
kubectl kustomize kubernetes/karpenter | sed "s/<CLUSTER_NAME>/$CLUSTER_NAME/g" | kubectl apply -f -
```

## AWS infrastructure

Terraform in [`aws/`](aws/) creates an EKS cluster in each of two regions, each in its own VPC across 3 availability zones, using the [`terraform-aws-modules`](https://github.com/terraform-aws-modules) VPC and EKS modules.

| Path | What it is |
| --- | --- |
| `aws/modules/eks-cluster/` | Reusable module: one VPC and one EKS cluster in the provider's region |
| `aws/regions/us-east-1/` | Cluster `mlops-us-east-1`, VPC `10.0.0.0/16` |
| `aws/regions/us-west-2/` | Cluster `mlops-us-west-2`, VPC `10.1.0.0/16` |

Each region is a separate Terraform root with its own state, so an outage or a failed apply in one region doesn't block changes to the other. VPC CIDRs don't overlap, so the VPCs can be peered or joined with a Transit Gateway later. To add a region, copy one of the `regions/` folders and change the region, cluster name, and CIDR.

Per cluster:

- **VPC**: per AZ, a private `/20` for nodes and pods, a public `/24` for load balancers and NAT, and an intra `/24` for the EKS control plane. One NAT gateway per AZ by default (`single_nat_gateway = true` to save cost).
- **EKS**: control plane in the intra subnets, nodes in the private subnets, public API endpoint, core add-ons (CoreDNS, kube-proxy, VPC CNI, Pod Identity Agent), and a managed node group of `m6i.large` (2–5 nodes, 3 desired).
- **External Secrets IAM**: a role `<cluster_name>-external-secrets` that can read Secrets Manager secrets matching `external_secrets_secret_prefixes` (default `mlops/*`) in the cluster's region, linked by EKS Pod Identity to the `external-secrets` service account in the `external-secrets` namespace. Used by [`kubernetes/secret-rotation/`](kubernetes/secret-rotation/). Add `external_secrets_kms_key_arns` if the secrets use a customer-managed KMS key.
- **Vault KMS**: a KMS key `alias/vault-unseal-<cluster_name>` (yearly rotation, 30-day deletion window) and a role `<cluster_name>-vault` allowed to encrypt and decrypt with it, linked by EKS Pod Identity to the `vault` service account in the `vault` namespace. Used by [`kubernetes/vault/`](kubernetes/vault/) for auto-unseal.
- Private subnets and the node security group are tagged `karpenter.sh/discovery=<cluster_name>`, matching [`kubernetes/karpenter/`](kubernetes/karpenter/) (set `CLUSTER_NAME` to the region's cluster when applying it).

```bash
cd aws/regions/us-east-1              # then repeat for us-west-2
terraform init
terraform apply
$(terraform output -raw configure_kubectl)
```

Creating a cluster takes about 15 minutes. EKS, NAT gateways, and nodes are billed while they run, in every region; `terraform destroy` in each region folder removes everything.

## AWS setup

The AWS S3 List workflow uses GitHub's OIDC provider to assume an IAM role, so no AWS access keys are stored in GitHub. One-time setup:

1. Register GitHub as an identity provider in your AWS account:

   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com
   ```

2. Create a role that only this repository can assume (replace `<ACCOUNT_ID>`):

   ```bash
   cat > trust.json <<'EOF'
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
       "Action": "sts:AssumeRoleWithWebIdentity",
       "Condition": {
         "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
         "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:iamsandipan/mlops:*" }
       }
     }]
   }
   EOF
   aws iam create-role --role-name github-actions-mlops --assume-role-policy-document file://trust.json
   aws iam attach-role-policy --role-name github-actions-mlops \
     --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
   ```

3. In **Settings → Secrets and variables → Actions → Variables**, add:
   - `AWS_ROLE_ARN`: `arn:aws:iam::<ACCOUNT_ID>:role/github-actions-mlops`
   - `AWS_REGION` (optional, defaults to `us-east-1`)
