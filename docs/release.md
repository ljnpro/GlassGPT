# Release Workflow

## Source Of Truth

- default branch: `main`
- active stable branch: `codex/stable-4.6`
- frozen backup branch: `codex/stable-4.5`
- version/build source of truth: `ios/GlassGPT/Config/Versions.xcconfig`
- local publishing credentials: `.local/publish.env`
- local release helper: `.local/one_click_release.sh`

## Tracked Release Command

```bash
./scripts/release_testflight.sh 4.6.1 <build-number> --branch codex/stable-4.6
```

The wrapper runs release-readiness, full CI gates, archive/export, IPA verification, TestFlight upload, and release commit/tag creation.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/ci.sh maintainability`
3. `./scripts/ci.sh release-readiness`
4. manual parity checklist from `docs/parity-baseline.md`
5. clean worktree
6. branch is `codex/stable-4.6`
7. version/build match the intended 4.6.1 candidate

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. capture the TestFlight Delivery UUID
2. verify `codex/stable-4.6` points to the release commit
3. verify `v4.6.1` points to the same commit
4. verify `git ls-remote` shows `codex/stable-4.6`, `main`, and `v<marketing-version>` aligned
5. preserve the backup tag and source bundle
