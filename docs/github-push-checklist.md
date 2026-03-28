# GitHub Push Checklist

## Purpose

Use this checklist only after the local release path is already clean.
Do not push first and debug later. Local CI, release logs, and the TestFlight
upload must already be complete before starting the GitHub phase.

## Preconditions

- current branch is the active release-preparation branch or the mirrored 5.0 release branch:
  - `feature/beta-5.0-cloudflare-all-in`
  - `codex/feature/beta-5.0-cloudflare-all-in`
  - `stable-5.0`
  - `codex/stable-5.0`
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

1. Push `HEAD` to the active release branch.
2. Push the release tag that points to the same commit.
3. Verify the remote refs with `git ls-remote`.
4. Watch the GitHub Actions run for that branch.
5. Read every remote log, not only failing jobs.
6. If anything is noisy or incorrect, fix locally, commit, push, and watch again.
7. Promote `main` only after the release branch is clean.
8. Preserve the pre-5.0 rollback line when promoting `main`.

## Remote CI Standard

Remote CI is only acceptable when every job log is clean:

- `0` warnings
- `0` errors
- `0` skipped tests
- `0` missing-tool noise
- `0` avoidable informational spam

Passing status alone is not enough. Successful logs still need manual review.

## Branch Promotion

When promoting the first 5.0 line to `main`:

- preserve the previous rollback line first when needed
- fast-forward `main` when possible
- if a force update is required, use `--force-with-lease`
- verify `main`, the release branch, the preserved rollback branch when used, and the release tag all point to the intended commit

## Post-Push Verification

1. Inspect every job log in GitHub Actions.
2. Confirm the release branch and `main` show the same release commit when expected.
3. Confirm the release tag points to the same commit.
4. Confirm no extra release commit or tag was created accidentally.
5. Keep the Delivery UUID and remote run URL in the release notes or handoff notes.
