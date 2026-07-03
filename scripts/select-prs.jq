# Classifies each open Dependabot PR as eligible for auto-merge or not, and says
# why when not.
#
# Input: the JSON array from `gh pr list --json
# number,createdAt,updatedAt,mergeable,statusCheckRollup,labels`.
# Output: one tab-separated record per PR, in input order:
#   <number>\t<ELIGIBLE|SKIP>\t<reason>
# `reason` is empty for ELIGIBLE rows, otherwise a human-readable explanation of
# the first failing condition (conditions are checked in a fixed order).
#
# A PR qualifies when it carries none of the skip labels, is mergeable, has aged
# past the cooldown (both when opened and its last activity), and every check is
# green. Reads three environment variables:
#   COOLDOWN_CUTOFF  unix seconds; PRs newer than this are too fresh to merge.
#   SKIP_LABELS      comma-separated label names to exclude (may be empty).
#   REQUIRE_CHECKS   "false" to allow an empty check rollup; otherwise require >=1.

# A check's display name, falling back across the shapes gh returns for check
# runs (.name) and legacy commit statuses (.context).
def check_name: .name // .context // "unnamed";

(env.COOLDOWN_CUTOFF | tonumber) as $cutoff
| (env.SKIP_LABELS
    | split(",")
    | map(gsub("^\\s+|\\s+$"; ""))
    | map(select(length > 0))) as $skips
| (env.REQUIRE_CHECKS != "false") as $require_checks
| .[]
| (.labels | map(.name) | map(select(IN($skips[])))) as $matched_skips
| (.statusCheckRollup
    | map(select(((.conclusion // .state)
        | . == "SUCCESS" or . == "NEUTRAL" or . == "SKIPPED") | not))
    | map(check_name)) as $bad_checks
| (if ($matched_skips | length) > 0 then
     "carries skip label: " + ($matched_skips | join(", "))
   elif .mergeable != "MERGEABLE" then
     "not mergeable (mergeable=" + (.mergeable // "null") + ")"
   elif (.createdAt | fromdateiso8601) > $cutoff then
     "too fresh: opened " + .createdAt + ", still within cooldown"
   elif (.updatedAt | fromdateiso8601) > $cutoff then
     "too fresh: last activity " + .updatedAt + ", still within cooldown"
   elif $require_checks and (.statusCheckRollup | length) == 0 then
     "no checks have run (set require-checks: false to merge without checks)"
   elif ($bad_checks | length) > 0 then
     "checks not green: " + ($bad_checks | join(", "))
   else
     ""
   end) as $reason
| [(.number | tostring), (if $reason == "" then "ELIGIBLE" else "SKIP" end), $reason]
| @tsv
