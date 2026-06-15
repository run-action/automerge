#!/usr/bin/env bash
#
# Enable auto-merge for open Dependabot PRs that are aged past the cooldown and
# fully green. Driven by the composite action in ../action.yml.
#
# Required environment:
#   GH_TOKEN          Token used by `gh` to query and merge PRs.
#   COOLDOWN_DAYS     Days a PR must age before it is eligible.
#   SKIP_LABELS       Comma-separated labels that exclude a PR (optional, may
#                     be unset/empty).
#   GITHUB_REPOSITORY owner/name of the repo (set by the Actions runner).
set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COOLDOWN_CUTOFF="$(date -u -d "${COOLDOWN_DAYS} days ago" +%s)"
export COOLDOWN_CUTOFF
# Default to empty so the filter is a no-op (no exclusions) when unset.
export SKIP_LABELS="${SKIP_LABELS:-}"

# The eligibility filter lives in select-prs.jq so it can be unit-tested against
# fixtures without GitHub (see tests/). gh's --jq reads COOLDOWN_CUTOFF and
# SKIP_LABELS from the environment exported above.
prs_json="$(
  gh pr list \
    --repo "$GITHUB_REPOSITORY" \
    --author "app/dependabot" \
    --state open \
    --json number,createdAt,commits,mergeable,statusCheckRollup,labels \
    --jq "$(cat "$SCRIPT_DIR/select-prs.jq")"
)"
mapfile -t prs < <(printf '%s' "$prs_json")

if [ "${#prs[@]}" -eq 0 ]; then
  echo "No eligible Dependabot PRs."
  exit 0
fi

# Process every PR even if one fails, then exit non-zero if any did, so a single
# bad PR doesn't strand the rest of the batch until the next scheduled run.
failed=0
for pr in "${prs[@]}"; do
  echo "::notice::Enabling auto-merge for PR #${pr}"
  if ! gh pr merge "$pr" --repo "$GITHUB_REPOSITORY" --auto --squash --delete-branch; then
    echo "::error::Could not enable auto-merge for PR #${pr}. Enable it under Settings -> General -> Pull Requests -> 'Allow auto-merge' in $GITHUB_REPOSITORY."
    failed=1
  fi
done

exit "$failed"
