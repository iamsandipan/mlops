---
name: add-workflow
description: Add a new GitHub Actions workflow to this repo following its conventions. Use when asked to create, add, or scaffold a GitHub Actions workflow.
---

# Add a GitHub Actions workflow

1. Put the file in `.github/workflows/<name>.yml` at the repo root. Workflows anywhere else are ignored by GitHub.
2. Follow the conventions of the existing workflows:
   - Pin actions to a major version (`actions/checkout@v4`).
   - Declare a minimal `permissions:` block; add only what the workflow needs (e.g. `id-token: write` for AWS OIDC, `actions: write` to dispatch other workflows).
   - Pass `${{ inputs.* }}` and other expressions into `run:` steps through `env:` rather than interpolating them into the script.
   - For AWS access, use `aws-actions/configure-aws-credentials@v4` with `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`; never store AWS access keys as secrets.
3. Add a row for the workflow to the Workflows table in `README.md`, and document any new repo variables or secrets it needs.
4. Note that `workflow_dispatch` workflows only appear in the Actions tab once the file is on the default branch (`master`).
