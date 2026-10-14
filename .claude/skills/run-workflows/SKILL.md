---
name: run-workflows
description: Run several GitHub Actions workflows in this repo one after another, waiting for each to finish and stopping at the first failure. Use when asked to run, chain, or sequence multiple workflows.
---

# Run workflows in sequence

Use `run_sequence.sh` in this skill's folder. It dispatches each workflow, waits for that run to finish, and only then starts the next. It stops at the first run that does not succeed.

## Prerequisites

- GitHub CLI installed and logged in: `brew install gh && gh auth login`. If `gh` is missing or not authenticated, tell the user to run that command as `! brew install gh && gh auth login` and stop.
- Every workflow in the list must have a `workflow_dispatch` trigger and exist on the default branch (`master`). Check `.github/workflows/` before running.

## Usage

```bash
.claude/skills/run-workflows/run_sequence.sh [--ref <branch>] <workflow>[:key=value,key=value] ...
```

- `<workflow>` is the file name in `.github/workflows/`, e.g. `build.yml`.
- Inputs go after a colon as comma-separated `key=value` pairs.
- `--ref` picks the branch to run on; defaults to `master`.

Example: build, then list S3, then deploy to staging:

```bash
.claude/skills/run-workflows/run_sequence.sh build.yml aws-s3-ls.yml downstream.yml:environment=staging,triggered_by=sequence
```

## Steps

1. Confirm the list of workflows and their inputs with the user if they did not spell them out. Runs can touch real infrastructure (e.g. AWS), so do not guess inputs like `environment=production`.
2. Run the script from the repo root with `run_in_background`, since workflows can take minutes. Wait for it to exit instead of polling.
3. Report each workflow's result and run URL from the script's output. On failure, name the workflow that failed, show its run URL, and offer to fetch its logs with `gh run view <run-id> --log-failed`.
