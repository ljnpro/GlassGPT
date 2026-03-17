# Release Workflow

## Source of Truth

- Default branch: `main`
- Stable 4.1 branch is read-only: `codex/stable-4.1`
- 4.2 release branch: `codex/stable-4.2` (maintenance only)
- 4.3 release branch: `codex/stable-4.3`
- 4.3.1 development work happens on `codex/feature/<topic>`
- version/build source of truth is `ios/GlassGPT/Config/Versions.xcconfig`
- Local credentials remain in `.local/publish.env`
- Local machine-specific release helper remains `.local/one_click_release.sh`

## Tracked Release Entry Point

Use the tracked wrapper:

```bash
./scripts/release_testflight.sh 4.3.1 <build-number> --branch codex/stable-4.3
```

The wrapper validates release-readiness, then runs:
1. release-readiness
2. lint/build/core-tests/ui-tests/maintainability
3. archive
4. export
5. IPA metadata verify
6. TestFlight upload
7. commit/version bump, tag, push, remote-ref verification

`local` credentials (`.local/publish.env`, `.local/one_click_release.sh`) are still required for auth and repo context.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/ci.sh maintainability`
3. `./scripts/ci.sh release-readiness`
4. manual parity checklist from `docs/parity-baseline.md`
5. verify clean worktree
6. verify branch is `codex/stable-4.3` (or `main` for backfilled maintenance)
7. verify release version/build number (4.3.1 / 20172 baseline)
8. verify `.local/build` artifacts and logs exist from the release attempt

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. Save TestFlight Delivery UUID
2. Verify branch `codex/stable-4.3` moved to release commit
3. Verify release tag `v4.3.1` exists and points to release commit
4. Verify `git ls-remote` shows `codex/stable-4.3`, `main`, and `v<marketing-version>` on the expected commit
5. Preserve the pre-release backup tag and bundle for rollback/reference
