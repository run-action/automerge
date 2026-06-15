# Selects the numbers of Dependabot PRs eligible for auto-merge.
#
# Input: the JSON array from `gh pr list --json
# number,createdAt,commits,mergeable,statusCheckRollup,labels`.
# Output: one eligible PR number per line.
#
# A PR qualifies when it carries none of the skip labels, is mergeable, has aged
# past the cooldown (both when it was opened and its last commit), and every
# check is green. Reads two environment variables:
#   COOLDOWN_CUTOFF  unix seconds; PRs newer than this are too fresh to merge.
#   SKIP_LABELS      comma-separated label names to exclude (may be empty).
(env.COOLDOWN_CUTOFF | tonumber) as $cutoff
| (env.SKIP_LABELS
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))) as $skips
| .[]
| select(any(.labels[].name; IN($skips[])) | not)
| select(.mergeable == "MERGEABLE")
| select((.createdAt | fromdateiso8601) <= $cutoff)
| select((.commits[-1].committedDate | fromdateiso8601) <= $cutoff)
| select((.statusCheckRollup | length) > 0)
| select(all(.statusCheckRollup[];
    (.conclusion // .state) as $s
    | $s == "SUCCESS" or $s == "NEUTRAL" or $s == "SKIPPED"))
| .number
