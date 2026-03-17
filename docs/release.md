# Release Workflow

## Source of Truth

- Default branch: `main`
- Stable 4.1 branch is read-only: `codex/stable-4.1`
- 4.2 release branch: `codex/stable-4.2` (maintenance only)
- 4.3 release branch: `codex/stable-4.3`
- 4.3 development work happens on `codex/feature/<topic>`
- Local credentials remain in `.local/publish.env`
- Local machine-specific release helper remains `.local/one_click_release.sh`

## Tracked Release Entry Point

Use the tracked wrapper:

```bash
./scripts/release_testflight.sh 4.3.0 <build-number> --branch codex/stable-4.3
```

The wrapper validates release-readiness, then runs:
1. archive
2. export
3. IPA metadata verify
4. TestFlight upload
5. commit/version bump, tag, push

`local` credentials (`.local/publish.env`, `.local/one_click_release.sh`) are still required for auth and repo context.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/ci.sh release-readiness`
3. manual parity checklist from `docs/parity-baseline.md`
4. verify clean worktree
5. verify branch is `codex/stable-4.3` (or `main` for backfilled maintenance)
6. verify release version/build number (4.3.0 / 20171 baseline)
7. verify `.local/build` artifacts and logs exist from the release attempt

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. Save TestFlight Delivery UUID
2. Verify branch `codex/stable-4.3` moved to release commit
3. Verify release tag `v4.3.0` exists and points to release commit
4. Push `codex/stable-4.3`
5. Push `v<marketing-version>` tag
6. Fast-forward `main` to the same release commit after tag validation
7. Preserve the pre-release backup tag and bundle for rollback/reference
