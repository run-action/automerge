#!/usr/bin/env bats
#
# Unit tests for scripts/select-prs.jq — the PR eligibility filter. These run
# the real filter against tests/fixtures/prs.json with no GitHub involved.
#
# The fixture cutoff is 2023-06-01T00:00:00Z (1685577600). Relative to it the
# fixtures cover: green+aged+clean (1,3), the skip label (2), too-fresh by
# open date (4) and by last commit (5), a failing check (6), no checks (7),
# NEUTRAL/SKIPPED/state-fallback green (8), and not-mergeable (9).

FILTER="scripts/select-prs.jq"
FIXTURE="tests/fixtures/prs.json"
export COOLDOWN_CUTOFF=1685577600

# The filter emits one "<number>\tELIGIBLE|SKIP\t<reason>" record per PR. The
# helpers below pull the field under test out of that so assertions read as a
# single stable string.

# Comma-joined numbers of the ELIGIBLE PRs.
run_filter() {
  SKIP_LABELS="$1" jq -r -f "$FILTER" "$FIXTURE" \
    | awk -F'\t' '$2 == "ELIGIBLE" { print $1 }' | paste -sd, -
}

# Same, but against an inline JSON document instead of the shared fixture. Used
# for edge cases that would otherwise perturb the fixture's stable expected
# output (other tests assert exact strings like "1,3,8"). SKIP_LABELS defaults
# to the production default so these focus on the property under test.
run_filter_json() {
  local json="$1"
  SKIP_LABELS="${2:-no-auto-merge}" jq -r -f "$FILTER" <<<"$json" \
    | awk -F'\t' '$2 == "ELIGIBLE" { print $1 }' | paste -sd, -
}

# The SKIP reason reported for a single-PR inline document. SKIP_LABELS defaults
# to the production default.
reason_for_json() {
  local json="$1"
  SKIP_LABELS="${2:-no-auto-merge}" jq -r -f "$FILTER" <<<"$json" \
    | awk -F'\t' '{ print $3 }'
}

# A single green, aged, mergeable PR with one passing check. Tests tweak one
# field to isolate the branch they exercise. createdAt/committedDate sit exactly
# at the cutoff (2023-06-01T00:00:00Z == 1685577600) so the <= boundary holds.
pr() {
  cat <<JSON
[{
  "number": 10,
  "createdAt": "2023-06-01T00:00:00Z",
  "commits": [{"committedDate": "2023-06-01T00:00:00Z"}],
  "mergeable": "MERGEABLE",
  "statusCheckRollup": [{"conclusion": "SUCCESS"}],
  "labels": []
}]
JSON
}

@test "default skip label 'no-auto-merge' excludes #2, keeps the green aged PRs" {
  run run_filter "no-auto-merge"
  [ "$status" -eq 0 ]
  [ "$output" = "1,3,8" ]
}

@test "empty skip-labels disables exclusion, so labeled #2 is included" {
  run run_filter ""
  [ "$status" -eq 0 ]
  [ "$output" = "1,2,3,8" ]
}

@test "multiple skip labels (trimmed) drop both #2 and #8" {
  run run_filter " no-auto-merge , wip "
  [ "$status" -eq 0 ]
  [ "$output" = "1,3" ]
}

@test "a PR too fresh by open date (#4) is excluded" {
  run run_filter "no-auto-merge"
  [[ "$output" != *"4"* ]]
}

@test "a PR whose last commit is too fresh (#5) is excluded" {
  run run_filter "no-auto-merge"
  [[ "$output" != *"5"* ]]
}

@test "a PR with a failing check (#6) is excluded" {
  run run_filter "no-auto-merge"
  [[ "$output" != *"6"* ]]
}

@test "a PR with no checks (#7) is excluded" {
  run run_filter "no-auto-merge"
  [[ "$output" != *"7"* ]]
}

@test "a non-mergeable PR (#9) is excluded" {
  run run_filter "no-auto-merge"
  [[ "$output" != *"9"* ]]
}

@test "a PR opened and committed exactly at the cutoff is included (<= boundary)" {
  run run_filter_json "$(pr)"
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
}

@test "one second past the cutoff (open date) is too fresh and excluded" {
  json="$(pr | jq -c '.[0].createdAt = "2023-06-01T00:00:01Z" | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "one second past the cutoff (last commit) is too fresh and excluded" {
  json="$(pr | jq -c '.[0].commits[-1].committedDate = "2023-06-01T00:00:01Z" | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "a PENDING (in-progress) check is not green and excludes the PR" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [{"conclusion": "SUCCESS"}, {"conclusion": "PENDING"}] | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "mergeable UNKNOWN (not yet computed) is excluded" {
  json="$(pr | jq -c '.[0].mergeable = "UNKNOWN" | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "a null conclusion falls back to .state, and a failing state is excluded" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [{"conclusion": null, "state": "FAILURE"}] | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "skip-label matching is exact, not substring: 'no-auto-merge-x' is kept" {
  json="$(pr | jq -c '.[0].labels = [{"name": "no-auto-merge-x"}] | .')"
  run run_filter_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "10" ]
}

@test "empty input array yields no eligible PRs" {
  run run_filter_json "[]"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- skip reasons -----------------------------------------------------------

@test "skip reason names the matched skip label" {
  json="$(pr | jq -c '.[0].labels = [{"name": "no-auto-merge"}] | .')"
  run reason_for_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "carries skip label: no-auto-merge" ]
}

@test "skip reason reports the mergeable state for a conflicting PR" {
  json="$(pr | jq -c '.[0].mergeable = "CONFLICTING" | .')"
  run reason_for_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "not mergeable (mergeable=CONFLICTING)" ]
}

@test "skip reason explains a too-fresh open date" {
  json="$(pr | jq -c '.[0].createdAt = "2023-06-02T00:00:00Z" | .')"
  run reason_for_json "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == "too fresh: opened 2023-06-02T00:00:00Z"* ]]
}

@test "skip reason names the non-green checks" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [{"name": "build", "conclusion": "FAILURE"}, {"name": "lint", "conclusion": "PENDING"}, {"name": "test", "conclusion": "SUCCESS"}] | .')"
  run reason_for_json "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "checks not green: build, lint" ]
}

@test "an eligible PR has an empty reason" {
  run reason_for_json "$(pr)"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# --- require-checks ---------------------------------------------------------

@test "with REQUIRE_CHECKS unset, a PR with no checks is skipped (no checks reason)" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [] | .')"
  run reason_for_json "$json"
  [ "$status" -eq 0 ]
  [[ "$output" == "no checks have run"* ]]
}

@test "with REQUIRE_CHECKS=false, a PR with no checks is eligible" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [] | .')"
  run env REQUIRE_CHECKS=false bash -c \
    'SKIP_LABELS=no-auto-merge jq -r -f "$1" <<<"$2" | awk -F"\t" "{ print \$2 }"' \
    _ "$FILTER" "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "ELIGIBLE" ]
}

@test "REQUIRE_CHECKS=false still rejects a PR whose checks are failing" {
  json="$(pr | jq -c '.[0].statusCheckRollup = [{"name": "build", "conclusion": "FAILURE"}] | .')"
  run env REQUIRE_CHECKS=false bash -c \
    'SKIP_LABELS=no-auto-merge jq -r -f "$1" <<<"$2" | awk -F"\t" "{ print \$3 }"' \
    _ "$FILTER" "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "checks not green: build" ]
}
