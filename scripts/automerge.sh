#!/usr/bin/env bash
#
# Enable auto-merge for open Dependabot PRs that are aged past the cooldown and
# fully green. Driven by the composite action in ../action.yml.
#
# Required environment:
#   GH_TOKEN          Token used by `gh` to query and merge PRs.
#   COOLDOWN_DAYS     Days a PR must age before it is eligible.
#   GITHUB_REPOSITORY owner/name of the repo (set by the Actions runner).
set -eu -o pipefail

COOLDOWN_CUTOFF="$(date -u -d "${COOLDOWN_DAYS} days ago" +%s)"
export COOLDOWN_CUTOFF

# The jq filter intentionally uses single quotes: $cutoff/$s are jq variables
# shellcheck disable=SC2016
prs_json="$(
  gh pr list \
    --repo "$GITHUB_REPOSITORY" \
    --author "app/dependabot" \
    --state open \
    --json number,createdAt,commits,mergeable,statusCheckRollup \
    --jq '
      (env.COOLDOWN_CUTOFF | tonumber) as $cutoff
      | .[]
      | select(.mergeable == "MERGEABLE")
      | select((.createdAt | fromdateiso8601) <= $cutoff)
      | select((.commits[-1].committedDate | fromdateiso8601) <= $cutoff)
      | select((.statusCheckRollup | length) > 0)
      | select(all(.statusCheckRollup[];
          (.conclusion // .state) as $s
          | $s == "SUCCESS" or $s == "NEUTRAL" or $s == "SKIPPED"))
      | .number
    '
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
