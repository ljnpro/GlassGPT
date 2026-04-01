# Release Workflow

## Source Of Truth

- live execution tracker:
  [todo.md](/Applications/GlassGPT/todo.md)
- full release plan:
  [2026-03-31-glassgpt-5.7.0-optimization.md](/Applications/GlassGPT/docs/superpowers/plans/2026-03-31-glassgpt-5.7.0-optimization.md)
- evidence-backed release audit:
  [audit-5.7.0.md](/Applications/GlassGPT/docs/audit-5.7.0.md)
- version/build source of truth:
  [Versions.xcconfig](/Applications/GlassGPT/ios/GlassGPT/Config/Versions.xcconfig)
- backend deploy helper:
  [deploy_backend.sh](/Applications/GlassGPT/scripts/deploy_backend.sh)
- TestFlight publish helper:
  [release_testflight.sh](/Applications/GlassGPT/scripts/release_testflight.sh)
- frozen rollback line:
  `stable-4.12` and `codex/stable-4.12`
- active 5.5 release line:
  `codex/stable-5.7`

## Canonical Release Command

Run the backend deploy and TestFlight publish directly on the release branch:

```bash
./scripts/deploy_backend.sh --env production
./scripts/release_testflight.sh 5.7.0 20226 --branch codex/stable-5.7 --skip-main-promotion
```

Preflight-only checks:

```bash
./scripts/release_testflight.sh 5.7.0 20226 --branch codex/stable-5.7 --skip-main-promotion --preflight-only
```

`release_5_3.sh` remains the historical 5.3-line orchestrator, but it is not
the primary entrypoint for the `5.7.0` release line.

## Release Order

Use this order on the `5.7.0` line:

1. verify a clean worktree on `codex/stable-5.7`
2. run full backend and iOS CI with zero-warning, zero-skipped output
3. generate or refresh the final CI evidence bundle
4. deploy backend to production through
   [deploy_backend.sh](/Applications/GlassGPT/scripts/deploy_backend.sh)
5. verify the production health and connection-check contract on version `5.7.0`
6. publish the iOS build to TestFlight through
   [release_testflight.sh](/Applications/GlassGPT/scripts/release_testflight.sh)
7. push the release branch and `v5.7.0` tag after both publications succeed

## Required Inputs

- `.local/backend.env`
- `.local/publish.env`
- a supported Transporter install at:
  `/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter`
- green `todo.md` exit gates
- [audit-5.7.0.md](/Applications/GlassGPT/docs/audit-5.7.0.md)
- final CI evidence at:
  `.local/build/evidence/rel-001-final-ci.txt`

## Pre-Release Checklist

1. `./scripts/ci.sh` passes on the exact release tree
2. the final CI evidence log exists and proves:
   - `0` warnings
   - `0` errors
   - `0` skipped tests
   - `0` avoidable noise
3. [todo.md](/Applications/GlassGPT/todo.md) exit gates are green
4. [audit-5.7.0.md](/Applications/GlassGPT/docs/audit-5.7.0.md) is current
5. the worktree is clean on the release branch
6. the intended version/build are written to
   [Versions.xcconfig](/Applications/GlassGPT/ios/GlassGPT/Config/Versions.xcconfig)
7. the frozen `stable-4.12` rollback line remains intact
8. Transporter is installed on this machine if TestFlight publication will run

## Output Artifacts

- `.local/build/GlassGPT-<version>.xcarchive`
- `.local/build/export-<version>/GlassGPT.ipa`
- `.local/build/archive-<version>.log`
- `.local/build/export-<version>.log`
- `.local/build/upload-<version>.log`
- `.local/build/backend-deploy.log`
- `.local/build/backend-migrations.log`
- `.local/build/backend-d1-backup.log`
- `.local/build/d1-<env>-backup-<timestamp>.sql`

## Backend D1 Backup And Restore

Before any live backend migration,
[deploy_backend.sh](/Applications/GlassGPT/scripts/deploy_backend.sh) exports
the target remote D1 database to a timestamped SQL file under `.local/build/`.

The supported restore/import helper is:

```bash
./scripts/restore_backend_d1.sh --env production --file .local/build/d1-production-backup-<timestamp>.sql --database-name <replacement-db-name> --yes
```

The intended recovery path is:

1. create a replacement D1 database
2. import the backup into that replacement database with
   [restore_backend_d1.sh](/Applications/GlassGPT/scripts/restore_backend_d1.sh)
3. update `.local/backend.env` so `BACKEND_<ENV>_D1_DATABASE_NAME` and
   `BACKEND_<ENV>_D1_DATABASE_ID` point at the replacement database
4. redeploy with:

```bash
./scripts/deploy_backend.sh --env <staging|production> --skip-migrations
```

5. rerun smoke checks and archive the import/deploy logs with the release
   evidence

## Post-Release Checklist

1. capture the TestFlight delivery UUID
2. verify the release branch points to the release commit locally
3. verify `v<marketing-version>` points to the same commit locally
4. if GitHub promotion runs, verify `git ls-remote` shows the intended release
   branch, the preserved rollback branch when used, and the release tag aligned
5. archive backend deploy, backup, import, export, and upload logs with the
   final release evidence bundle
