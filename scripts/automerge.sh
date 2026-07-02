#!/usr/bin/env bash
#
# Squash-merge open Dependabot PRs that are aged past the cooldown and fully
# green. Driven by the composite action in ../action.yml.
#
# Required environment:
#   GH_TOKEN          Token used by `gh` to query and merge PRs.
#   COOLDOWN_DAYS     Days a PR must age before it is eligible.
#   SKIP_LABELS       Comma-separated labels that exclude a PR (optional, may
#                     be unset/empty).
#   REQUIRE_CHECKS    "false" to merge PRs that have no checks at all (optional,
#                     defaults to "true").
#   GITHUB_REPOSITORY owner/name of the repo (set by the Actions runner).
set -eu -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

COOLDOWN_CUTOFF="$(($(date +%s) - COOLDOWN_DAYS * 86400))"
export COOLDOWN_CUTOFF
# Default to empty so the filter is a no-op (no exclusions) when unset.
export SKIP_LABELS="${SKIP_LABELS:-}"
# Default to requiring checks; only "false" relaxes the empty-rollup guard.
export REQUIRE_CHECKS="${REQUIRE_CHECKS:-true}"

# The classification filter lives in select-prs.jq so it can be unit-tested
# against fixtures without GitHub (see tests/). It emits one tab-separated record
# per open Dependabot PR: <number>\t<ELIGIBLE|SKIP>\t<reason>. gh's --jq reads
# COOLDOWN_CUTOFF, SKIP_LABELS and REQUIRE_CHECKS from the environment above.
classified="$(
  gh pr list \
    --repo "$GITHUB_REPOSITORY" \
    --author "app/dependabot" \
    --state open \
    --limit 100 \
    --json number,createdAt,commits,mergeable,statusCheckRollup,labels \
    --jq "$(cat "$SCRIPT_DIR/select-prs.jq")"
)"

if [ -z "$classified" ]; then
  echo "No eligible Dependabot PRs."
  exit 0
fi

# Process every PR even if one fails, then exit non-zero if any did, so a single
# bad PR doesn't strand the rest of the batch until the next scheduled run.
# Skipped PRs get a ::notice:: naming why, so a run that merges nothing still
# explains itself instead of looking like it found nothing.
failed=0
total=0
eligible=0
while IFS=$'\t' read -r number status reason; do
  [ -z "$number" ] && continue
  total=$((total + 1))
  if [ "$status" = "ELIGIBLE" ]; then
    eligible=$((eligible + 1))
    # The filter has already confirmed the PR is mergeable, aged, and green, so
    # merge directly rather than handing it to GitHub's auto-merge queue (which
    # needs a pending requirement to wait on and the repo's "Allow auto-merge"
    # setting; both are absent on repos without required checks).
    echo "::notice::Merging PR #${number}"
    if ! gh pr merge "$number" --repo "$GITHUB_REPOSITORY" --squash --delete-branch; then
      echo "::error::Could not merge PR #${number} in $GITHUB_REPOSITORY."
      failed=1
    fi
  else
    echo "::notice::Skipping PR #${number}: ${reason}"
  fi
done <<<"$classified"

if [ "$eligible" -eq 0 ]; then
  echo "${total} open Dependabot PR(s), none eligible — see the skip notices above."
fi

exit "$failed"
