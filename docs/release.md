# Release Workflow

## Source Of Truth

- default branch: `main`
- active local stable branch: `stable-4.12`
- remote stable branch when mirrored: `codex/stable-4.12`
- frozen prior stable branch: `codex/stable-4.11`
- version/build source of truth: `ios/GlassGPT/Config/Versions.xcconfig`
- tracked release wrapper: `scripts/release_testflight.sh`
- local publishing credentials: `.local/publish.env`
- optional local helper: `.local/one_click_release.sh` (local-only convenience, not part of the tracked release path)

## Tracked Release Command

```bash
PUSH_RELEASE=0 ./scripts/release_testflight.sh 4.12.0 20199 --branch stable-4.12 --skip-main-promotion --skip-ci
```

The wrapper always runs `release-readiness`, archive/export, IPA verification,
TestFlight upload, and release commit/tag creation. `--skip-ci` is only
acceptable after the exact same tree has already passed a full local
`./scripts/ci.sh` run. It skips only the second full CI pass; it does not skip
`release-readiness`.

If the branch is being mirrored to GitHub and `main` has diverged from the
stable line, preserve the current remote `main` tip before promotion:

```bash
./scripts/release_testflight.sh 4.12.0 20199 --branch codex/stable-4.12 --preserve-main-as codex/stable-4.11 --force-main-with-lease
```

For a dry run of the release wrapper's branch, version, and remote-topology
checks without running CI or archive/upload work:

```bash
./scripts/release_testflight.sh 4.12.0 20199 --branch stable-4.12 --preflight-only
```

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/score_4_8_1.sh`
3. `./scripts/score_4_8_2.sh`
4. any release-specific `4.12.0` scoring or verification scripts
5. manual parity checklist from `docs/parity-baseline.md`
6. clean worktree on `stable-4.12`
7. version/build match the intended `4.12.0 (20199 or next available)` candidate
8. Phase G has been re-evaluated and the ADR updated before release
9. workflow triggers and readiness docs all reference `stable-4.12` locally and `codex/stable-4.12` for GitHub mirroring
10. if `main` is not an ancestor of the release commit, choose the preserve branch and use `--force-main-with-lease`

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. capture the TestFlight Delivery UUID
2. verify `stable-4.12` points to the release commit locally
3. verify `v4.12.0` points to the same commit locally
4. if the GitHub phase runs later, verify `git ls-remote` shows `codex/stable-4.12`, `main`, `codex/stable-4.11`, and `v<marketing-version>` aligned
5. preserve the prior stable backup tag and source bundle
