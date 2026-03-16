# Release Workflow

## Source of Truth

- Stable 4.1 branch is read-only: `codex/stable-4.1`
- 4.2 release branch: `codex/stable-4.2`
- Local credentials remain in `.local/publish.env`
- Local machine-specific release helper remains `.local/one_click_release.sh`

## Tracked Release Entry Point

Use the tracked wrapper:

```bash
./scripts/release_testflight.sh 4.2.0 <build-number> --branch codex/stable-4.2
```

The wrapper delegates to `.local/one_click_release.sh` so tracked source never stores credentials.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. manual parity checklist from `docs/parity-baseline.md`
3. verify clean worktree
4. verify branch is `codex/stable-4.2`
5. verify release version/build number

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. Save TestFlight Delivery UUID
2. Push branch
3. Tag release as `v<marketing-version>`
4. Confirm the tag exists on GitHub
