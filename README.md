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
  `NEUTRAL`, or `SKIPPED`),

and enables auto-merge (`--auto --squash --delete-branch`) on each.

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

| Input           | Default               | Description                                                                                             |
| --------------- | --------------------- | ------------------------------------------------------------------------------------------------------- |
| `cooldown-days` | `3`                   | Days a Dependabot PR must age before it is eligible to merge.                                           |
| `skip-labels`   | `no-auto-merge`       | Comma-separated labels that exclude a PR from auto-merge. Set to `""` to disable label-based exclusion. |
| `github-token`  | `${{ github.token }}` | Token used to query and merge PRs.                                                                      |

## Prerequisites

- **"Allow auto-merge" must be enabled** in the consuming repo's settings
  (Settings → General → Pull Requests). Without it, `gh pr merge --auto` errors.
  Enable it from the CLI with:

  ```sh
  gh repo edit <owner>/<repo> --enable-auto-merge
  ```
- The calling job must grant `contents: write` and `pull-requests: write`, as in
  the example above. An action runs with the permissions of its calling job.

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
