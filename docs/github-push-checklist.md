# GitHub Push Checklist

## Purpose

Use this checklist after the local release path is already clean.
Do not push first and debug later. Local CI, release logs, and TestFlight upload
must already be complete before starting the GitHub phase.

## Preconditions

- current branch is the active stable branch, usually `codex/stable-4.11`
- worktree is clean
- `ios/GlassGPT/Config/Versions.xcconfig` matches the intended release
- `.local/build` logs were reviewed manually
- local logs contain:
  - `0` warnings
  - `0` errors
  - `0` skipped tests
  - `0` irrelevant noise
- TestFlight upload already succeeded and the Delivery UUID was recorded

## Authentication

- use the personal GitHub PAT from `.local/publish.env`
- push with the account that owns the release branch
- avoid ad hoc credential changes in the repo config
- prefer one-shot authenticated push commands or temporary process-scoped auth

## Push Order

1. Push `HEAD` to the active stable branch.
2. Push the release tag that points to the same commit.
3. Verify the remote refs with `git ls-remote`.
4. Watch the GitHub Actions run for the stable branch.
5. Read every remote log file, not only failing jobs.
6. If anything is noisy or incorrect, fix locally, commit, push, and watch again.
7. Only after the stable branch is clean, promote `main`.
8. Keep the previous `main` commit preserved on the matching frozen stable branch.

## Remote CI Standard

Remote CI is only acceptable when every job log is clean:

- `0` warnings
- `0` errors
- `0` skipped tests
- `0` missing-tool noise
- `0` avoidable informational spam

Passing status alone is not enough. Successful logs still need manual review.

## Branch Promotion

When promoting a new stable line to `main`:

- preserve the previous `main` tip on the frozen branch first
- fast-forward `main` when possible
- if a force update is required, use `--force-with-lease`
- verify `main`, the stable branch, and the release tag all point to the intended commit

For the `4.11` rollout:

- previous `main` must remain available as `codex/stable-4.10`
- the released `4.11.x` commit becomes both `codex/stable-4.11` and `main`

## Post-Push Verification

After the remote workflow finishes:

1. Inspect every job log in GitHub Actions.
2. Confirm the stable branch and `main` show the same release commit when expected.
3. Confirm the release tag points to the same commit.
4. Confirm no extra release commit or tag was created accidentally.
5. Keep the Delivery UUID and remote run URL in the release notes or handoff notes.
