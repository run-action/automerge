# automerge

A composite GitHub Action for **delayed** Dependabot auto-merge: it
squash-merges Dependabot PRs only after they have aged past a cooldown and
every check is green.

## What it does

On each run it finds open Dependabot PRs that are **all** of:

- **not carrying a skip label** — by default any PR labelled `no-auto-merge` is
  left for human review (configurable via `skip-labels`),
- **mergeable** (`mergeable == MERGEABLE`),
- **older than `cooldown-days`** — a window for a yanked or malicious release to
  be caught before it lands,
- carry **at least one check**, with **every check green** (`SUCCESS`,
  `NEUTRAL`, or `SKIPPED`) — relax the "at least one check" part with
  `require-checks: false`,

and squash-merges each (`--squash --delete-branch`). Every PR that is skipped is
logged with the reason (`::notice::`), so a run that merges nothing still
explains why instead of looking like it found nothing.

## Usage

Add a workflow to the consuming repo. It owns the schedule, the permissions, and
the cooldown:

```yaml
# .github/workflows/automerge.yml
name: Dependabot auto-merge

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
    steps:
      - uses: run-action/automerge@v1
        with:
          cooldown-days: 3
```

See [`examples/automerge.yml`](examples/automerge.yml).

### Pinning (recommended)

It's recommended pin to a full commit SHA rather than a moving tag like `@v1`.

```yaml
- uses: run-action/automerge@<full-commit-sha> # v1.0.0
```

Let Dependabot keep the pin fresh by watching this action in the consuming repo:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

## Inputs

| Input           | Default             | Description                                                                                             |
| --------------- | ------------------- | ------------------------------------------------------------------------------------------------------- |
| `cooldown-days` | `3`                 | Days a Dependabot PR must age before it is eligible to merge.                                           |
| `skip-labels`   | `no-auto-merge`     | Comma-separated labels that exclude a PR from auto-merge. Set to `""` to disable label-based exclusion. |
| `require-checks`| `true`              | Require at least one check. Set to `false` to merge PRs with no checks, relying solely on the cooldown. |
| `github-token`  | `${{github.token}}` | Token used to query and merge PRs.                                                                      |

## Prerequisites

- The calling job must grant `contents: write` and `pull-requests: write`, as in
  the example above. An action runs with the permissions of its calling job.

The action merges directly (`gh pr merge --squash`) once it has confirmed a PR
is mergeable, aged, and green.

## `require-checks` and the cooldown

By default a PR must have at least one check before it can merge. Setting
`require-checks: false` lets PRs with **no** checks through — useful for repos
whose CI doesn't run on Dependabot PRs (e.g. workflows triggered only by
`workflow_dispatch`). The trade-off: an empty check rollup means *nothing*
validated the change, so eligibility then rests **entirely** on the cooldown
window catching a yanked or malicious release. Pick a cooldown you're
comfortable relying on alone before enabling this.

## Development

The merge logic lives in [`scripts/automerge.sh`](scripts/automerge.sh); the
composite action just sets env and invokes it.
The PR eligibility filter is in [`scripts/select-prs.jq`](scripts/select-prs.jq)
so it can be tested independently.

Linting and tests are driven by [`flake.nix`](flake.nix). It pulls the tools and
runs every check:

```sh
nix flake check -L       # shellcheck, actionlint, yamllint, nixfmt, bats tests
nix develop              # drop into a shell with all tools available
bats tests/              # run just the tests
```
