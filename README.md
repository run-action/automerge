# automerge

A composite GitHub Action for **delayed** Dependabot auto-merge: it
squash-merges Dependabot PRs only after they have aged past a cooldown and
every check is green.

## What it does

On each run it finds open Dependabot PRs that are **all** of:

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

## Inputs

| Input           | Default               | Description                                                   |
| --------------- | --------------------- | ------------------------------------------------------------- |
| `cooldown-days` | `3`                   | Days a Dependabot PR must age before it is eligible to merge. |
| `github-token`  | `${{ github.token }}` | Token used to query and merge PRs.                            |

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

Linting is driven by [`flake.nix`](flake.nix). It pulls the tools and runs every
check:

```sh
nix flake check -L       # shellcheck, actionlint, yamllint, nixfmt
nix develop              # drop into a shell with all four available
```
