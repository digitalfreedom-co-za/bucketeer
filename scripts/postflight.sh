#!/bin/sh
# postflight.sh — companion to preflight.sh. Run after `git push`
# to watch the GitHub Actions CI run land and surface the result.
#
# Why a separate script: preflight catches what we can verify
# locally; postflight catches what only the macos-15 runner sees
# (different Xcode, no cached DerivedData, fresh checkout).
#
# Usage:
#   sh scripts/postflight.sh           # watch the latest run on
#                                       # current branch
#   sh scripts/postflight.sh <runId>   # watch a specific run
#
# Requires: gh (https://cli.github.com/) authenticated to the
# bucketeer repository.

set -eu
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }

if ! command -v gh >/dev/null 2>&1; then
  red "gh CLI is not installed. Install via 'brew install gh' first."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  red "gh CLI is not authenticated. Run 'gh auth login' first."
  exit 1
fi

cd "$REPO_ROOT"

runID="${1:-}"
if [ -z "$runID" ]; then
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)"
  echo "Looking up latest CI run on '$branch' …"
  runID=$(gh run list --branch "$branch" --limit 1 --json databaseId \
            --jq '.[0].databaseId' 2>/dev/null || echo "")
  if [ -z "$runID" ]; then
    yellow "No run found yet for '$branch'. The workflow may need a few seconds to register."
    exit 0
  fi
fi

echo "Watching run #$runID"
gh run watch "$runID" --exit-status
status=$?
echo

if [ "$status" -eq 0 ]; then
  green "Run #$runID passed. Working tree is in a CI-clean state."
  exit 0
else
  red "Run #$runID failed (exit $status). Investigate with:"
  echo "  gh run view $runID --log-failed"
  exit "$status"
fi
