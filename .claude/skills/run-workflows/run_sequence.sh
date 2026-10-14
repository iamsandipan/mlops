#!/usr/bin/env bash
# Run GitHub Actions workflows one after another, stopping at the first failure.
# Usage: run_sequence.sh [--ref <branch>] <workflow>[:key=value,key=value] ...
set -euo pipefail

ref=master
if [ "${1:-}" = "--ref" ]; then
  ref="$2"
  shift 2
fi

if [ $# -eq 0 ]; then
  echo "Usage: $0 [--ref <branch>] <workflow>[:key=value,...] ..." >&2
  exit 2
fi

command -v gh >/dev/null || { echo "gh is not installed (brew install gh)" >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in (gh auth login)" >&2; exit 2; }

latest_run_id() {
  gh run list --workflow "$1" --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId // 0'
}

for spec in "$@"; do
  workflow="${spec%%:*}"
  args=(--ref "$ref")
  if [ "$spec" != "$workflow" ]; then
    IFS=',' read -r -a pairs <<< "${spec#*:}"
    for pair in "${pairs[@]}"; do
      args+=(-f "$pair")
    done
  fi

  before=$(latest_run_id "$workflow")
  echo "==> Dispatching $workflow on $ref"
  gh workflow run "$workflow" "${args[@]}"

  # The dispatch API does not return a run id, so wait for a newer run to appear.
  run_id=$before
  for _ in $(seq 1 30); do
    sleep 2
    run_id=$(latest_run_id "$workflow")
    [ "$run_id" != "$before" ] && break
  done
  if [ "$run_id" = "$before" ]; then
    echo "!! Run for $workflow did not start within 60s" >&2
    exit 1
  fi

  url=$(gh run view "$run_id" --json url --jq .url)
  echo "    Run $run_id: $url"
  if ! gh run watch "$run_id" --exit-status --interval 10 >/dev/null; then
    echo "!! $workflow failed: $url" >&2
    exit 1
  fi
  echo "    $workflow succeeded"
done

echo "==> All $# workflows succeeded"
