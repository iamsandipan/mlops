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

Plain manifests for an API live in [`kubernetes/api/`](kubernetes/api/): a Deployment (2 replicas, probes, resource limits, Prometheus scrape annotations) and a ClusterIP Service on port 80. The image is a placeholder (`hashicorp/http-echo`); swap in your own and adjust the container port.

```bash
kubectl apply -k kubernetes/api
```

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
