# automerge

A composite GitHub Action, **Gated automerge**, that squash-merges open
Dependabot PRs once they've aged past a cooldown and every check is green.

## Usage

```yaml
# .github/workflows/automerge.yml
name: Gated automerge
on:
  schedule:
    - cron: "17 6 * * *"
  workflow_dispatch: {}
permissions: {}
concurrency:
  group: dependabot-automerge-${{ github.repository }}
  cancel-in-progress: false
jobs:
  automerge:
    runs-on: ubuntu-24.04
    permissions:
      contents: write
      pull-requests: write
      checks: read
      statuses: read
      actions: read
    steps:
      - uses: run-action/automerge@46cd9d2f9e469f68f91b6c22e2a13f673ccac593 # v1.2.3
        with:
          cooldown-days: 3
```

Releases are immutable semver tags only — there is no floating `v1` major
tag. Pin to a full commit SHA and let Dependabot bump it. See
[`examples/automerge.yml`](examples/automerge.yml).

## Inputs

| Input            | Default             | Description                                                                                             |
| ---------------- | ------------------- | ------------------------------------------------------------------------------------------------------- |
| `cooldown-days`  | `3`                 | Days a Dependabot PR must age before it is eligible to merge.                                           |
| `skip-labels`    | `no-auto-merge`     | Comma-separated labels that exclude a PR from auto-merge. Set to `""` to disable label-based exclusion. |
| `require-checks` | `true`              | Require at least one check. Set to `false` to merge PRs with no checks, relying solely on the cooldown. |
| `auto-merge`     | `false`             | Enable GitHub auto-merge (`--auto`) instead of merging directly. Requires the repo's "Allow auto-merge" setting and a ruleset with at least one requirement; branch cleanup then follows the repo's "Automatically delete head branches" setting. |
| `github-token`   | `${{github.token}}` | Token used to query and merge PRs.                                                                      |

## Prerequisites

The calling job must grant all five scopes:

| Scope                  | Why                                                                 |
| ---------------------- | ------------------------------------------------------------------- |
| `contents: write`      | Merge the PR.                                                       |
| `pull-requests: write` | Enable auto-merge and delete the branch.                            |
| `checks: read`         | Read each PR's `statusCheckRollup` to confirm every check is green. |
| `statuses: read`       | Same rollup, used to confirm checks are green.                      |
| `actions: read`        | Same rollup, needed to read check runs from Actions workflow runs.  |

A `permissions:` block defaults any unlisted scope to `none`, so all five must
be named explicitly. Omitting the read scopes fails with
`Resource not accessible by integration (statusCheckRollup)`.

## Development

```sh
nix flake check -L   # shellcheck, actionlint, yamllint, nixfmt, bats tests
nix develop          # shell with all tools
bats tests/          # just the tests
```

Merge logic: [`scripts/automerge.sh`](scripts/automerge.sh). Eligibility filter:
[`scripts/select-prs.jq`](scripts/select-prs.jq) (unit-tested via
[`tests/`](tests/)).
