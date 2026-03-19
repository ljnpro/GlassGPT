# Release Workflow

## Source Of Truth

- default branch: `main`
- active stable branch: `codex/stable-4.9`
- frozen prior stable branch: `codex/stable-4.8`
- version/build source of truth: `ios/GlassGPT/Config/Versions.xcconfig`
- tracked release wrapper: `scripts/release_testflight.sh`
- local publishing credentials: `.local/publish.env`
- local release helper: `.local/one_click_release.sh`
- GitHub release workflow: `.github/workflows/release-testflight.yml`
- GitHub release environment: `testflight`

## Tracked Release Command

```bash
./scripts/release_testflight.sh 4.9.0 20183 --branch codex/stable-4.9
```

The wrapper always runs `release-readiness`, the full `./scripts/ci.sh` suite,
archive/export, IPA verification, TestFlight upload, and release commit/tag
creation. There are no CI bypass flags on the tracked path.

## GitHub Release Path

GitHub can run the same tracked release wrapper through the manual
`Release TestFlight` workflow in
`.github/workflows/release-testflight.yml`.

Required `testflight` environment secrets:

- `ASC_API_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_API_KEY_P8`
- `RELEASE_GITHUB_PAT`

The workflow materializes `.local/publish.env` and the App Store Connect API
key at runtime, then runs `./scripts/release_testflight.sh` with the supplied
version, build number, and target branch.

## Pre-Release Checklist

1. `./scripts/ci.sh`
2. `./scripts/score_4_8_1.sh`
3. `./scripts/score_4_8_2.sh`
4. any release-specific `4.9.0` scoring or verification scripts
5. manual parity checklist from `docs/parity-baseline.md`
6. clean worktree on `codex/stable-4.9`
7. version/build match the intended `4.9.0 (20183 or next available)` candidate
8. Phase G has been re-evaluated and the ADR updated before release
9. workflow triggers and readiness docs all reference `codex/stable-4.9`

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. capture the TestFlight Delivery UUID
2. verify `codex/stable-4.9` points to the release commit
3. verify `v4.9.0` points to the same commit
4. verify `git ls-remote` shows `codex/stable-4.9`, `main`, and `v<marketing-version>` aligned
5. preserve the `v4.8.2-backup-before-4.9.0` tag and source bundle
