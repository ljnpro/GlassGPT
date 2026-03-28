# Release Workflow

## Source Of Truth

- default branch: `main`
- active release-preparation branch: `feature/beta-5.0-cloudflare-all-in`
- optional remote mirror of the release-preparation branch: `codex/feature/beta-5.0-cloudflare-all-in`
- frozen rollback line: `stable-4.12` and `codex/stable-4.12`
- future stable 5.0 line, if created: `stable-5.0` and `codex/stable-5.0`
- version/build source of truth: `ios/GlassGPT/Config/Versions.xcconfig`
- tracked release wrapper: `scripts/release_testflight.sh`
- local publishing credentials: `.local/publish.env`
- optional local helper: `.local/one_click_release.sh` for personal convenience only

## Tracked Release Command

```bash
PUSH_RELEASE=0 ./scripts/release_testflight.sh 5.0.0 20206 --branch feature/beta-5.0-cloudflare-all-in --skip-main-promotion --skip-ci
```

The wrapper always runs `release-readiness`, archive/export, IPA verification,
TestFlight upload, and release commit/tag creation. `--skip-ci` is only
acceptable after the exact same tree has already passed the required hard lanes
and the logs for those runs were reviewed manually. It never skips
`release-readiness`.

If the GitHub phase is being executed and `main` is not a fast-forward target,
preserve the existing remote `main` tip before promotion:

```bash
./scripts/release_testflight.sh 5.0.0 20206 --branch codex/feature/beta-5.0-cloudflare-all-in --preserve-main-as codex/stable-4.12 --force-main-with-lease
```

For a dry run of the wrapper's branch, version, and remote-topology checks:

```bash
./scripts/release_testflight.sh 5.0.0 20206 --branch feature/beta-5.0-cloudflare-all-in --preflight-only
```

## Pre-Release Checklist

1. `./scripts/ci.sh contracts`
2. `./scripts/ci.sh backend`
3. `./scripts/ci.sh ios`
4. `./scripts/ci.sh release-readiness`
5. the exact release tree has clean logs with:
   - `0` warnings
   - `0` errors
   - `0` skipped tests
   - `0` avoidable noise
6. the product framing is current:
   - backend-owned execution
   - Sign in with Apple
   - same-account cloud sync
   - user-entered OpenAI API key stored encrypted on the backend
7. worktree is clean on the release branch
8. version/build match the intended `5.0.0` candidate
9. frozen rollback references remain intact for `stable-4.12`
10. if `main` is not an ancestor of the release commit, choose the preserve branch and use `--force-main-with-lease`

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`

## Post-Release Checklist

1. capture the TestFlight Delivery UUID
2. verify the release branch points to the release commit locally
3. verify `v5.0.0` points to the same commit locally
4. if the GitHub phase runs, verify `git ls-remote` shows the intended branch, `main` when promoted, the preserved rollback branch when used, and `v<marketing-version>` aligned
5. keep the frozen `stable-4.12` rollback line and prior backup tag/source bundle intact
