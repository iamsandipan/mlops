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

Run the manual workflows from **Actions → *workflow name* → Run workflow**.

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
