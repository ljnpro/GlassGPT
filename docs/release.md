# Release Workflow

## Source Of Truth

- default branch: `main`
- active stable branch: `codex/stable-4.10`
- frozen prior stable branch: `codex/stable-4.9`
- version/build source of truth: `ios/GlassGPT/Config/Versions.xcconfig`
- tracked release wrapper: `scripts/release_testflight.sh`
- local publishing credentials: `.local/publish.env`
- optional local helper: `.local/one_click_release.sh` (local-only convenience, not part of the tracked release path)

## Tracked Release Command

```bash
./scripts/release_testflight.sh 4.10.0 20185 --branch codex/stable-4.10
```

The wrapper always runs `release-readiness`, the full `./scripts/ci.sh` suite,
archive/export, IPA verification, TestFlight upload, and release commit/tag
creation. There are no CI bypass flags on the tracked path.

If `main` has diverged from the active stable branch, preserve the current
remote `main` tip before promotion:

```bash
./scripts/release_testflight.sh 4.10.0 20185 --branch codex/stable-4.10 --preserve-main-as codex/stable-4.9 --force-main-with-lease
```

For a dry run of the release wrapper's branch, version, and remote-topology
checks without running CI or archive/upload work:

```bash
./scripts/release_testflight.sh 4.10.0 20185 --branch codex/stable-4.10 --preflight-only
```

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/score_4_8_1.sh`
3. `./scripts/score_4_8_2.sh`
4. any release-specific `4.10.0` scoring or verification scripts
5. manual parity checklist from `docs/parity-baseline.md`
6. clean worktree on `codex/stable-4.10`
7. version/build match the intended `4.10.0 (20185 or next available)` candidate
8. Phase G has been re-evaluated and the ADR updated before release
9. workflow triggers and readiness docs all reference `codex/stable-4.10`
10. if `main` is not an ancestor of the release commit, choose the preserve branch and use `--force-main-with-lease`

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. capture the TestFlight Delivery UUID
2. verify `codex/stable-4.10` points to the release commit
3. verify `v4.10.0` points to the same commit
4. verify `git ls-remote` shows `codex/stable-4.10`, `main`, `codex/stable-4.9`, and `v<marketing-version>` aligned
5. preserve the prior stable backup tag and source bundle
