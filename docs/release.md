# Release Workflow

## Source of Truth

- Default branch: `main`
- Stable 4.1 branch is read-only: `codex/stable-4.1`
- 4.2 release branch: `codex/stable-4.2`
- 4.2 development work happens on `codex/feature/<topic>`
- Local credentials remain in `.local/publish.env`
- Local machine-specific release helper remains `.local/one_click_release.sh`

## Tracked Release Entry Point

Use the tracked wrapper:

```bash
./scripts/release_testflight.sh 4.2.2 <build-number> --branch codex/stable-4.2
```

The wrapper delegates to `.local/one_click_release.sh` so tracked source never stores credentials.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. manual parity checklist from `docs/parity-baseline.md`
3. verify clean worktree
4. verify branch is `codex/stable-4.2`
5. verify release version/build number
6. verify `main` still points to the previous stable release before the new release is tagged

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. Save TestFlight Delivery UUID
2. Push `codex/stable-4.2`
3. Tag release as `v<marketing-version>`
4. Fast-forward `main` to the same release commit
5. Confirm the branch and tag exist on GitHub
