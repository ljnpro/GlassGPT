# Backend Local Development

## Purpose

This document covers the current backend developer workflow for
`services/backend`, including the Cloudflare/D1 prerequisites used by local
validation and the staged release scripts.

## Prerequisites

- Node.js `>=22 <26`
- Corepack-enabled `pnpm`
- Python `3.14+`
- Wrangler available through the workspace install
- Cloudflare credentials for any command that talks to real remote resources

## Install

```bash
corepack enable
corepack pnpm install
```

## Local Validation

- Contracts:

```bash
./scripts/ci.sh contracts
```

- Backend lane:

```bash
./scripts/ci.sh backend
```

- Direct backend commands:

```bash
cd services/backend
corepack pnpm run build
corepack pnpm run test
corepack pnpm run check
```

## Environment Files

The backend build and test path does not require a `.env` file for basic local
typecheck/test work, but the deploy/release scripts read:

- `.local/backend.env`
- `.local/publish.env` for TestFlight publishing

An example backend env file is provided at
[services/backend/.env.example](/Applications/GlassGPT/services/backend/.env.example).

## Minimum Backend Env For Deploy Scripts

Required for scripted backend deploys:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Required for staged release environments:

- `BACKEND_STAGING_WORKER_NAME`
- `BACKEND_STAGING_D1_DATABASE_NAME`
- `BACKEND_STAGING_D1_DATABASE_ID`
- `BACKEND_STAGING_R2_BUCKET_NAME`
- `BACKEND_PRODUCTION_WORKER_NAME`
- `BACKEND_PRODUCTION_D1_DATABASE_NAME`
- `BACKEND_PRODUCTION_D1_DATABASE_ID`
- `BACKEND_PRODUCTION_R2_BUCKET_NAME`

Common optional overrides:

- `BACKEND_STAGING_APP_ENV`
- `BACKEND_PRODUCTION_APP_ENV`
- `BACKEND_STAGING_CORS_ALLOWED_ORIGINS`
- `BACKEND_PRODUCTION_CORS_ALLOWED_ORIGINS`
- `BACKEND_STAGING_HEALTHCHECK_URL`
- `BACKEND_PRODUCTION_HEALTHCHECK_URL`

## Release-Oriented Commands

- Dry-run staged deploy validation:

```bash
./scripts/deploy_backend.sh --env staging --dry-run
```

- Live staged deploy:

```bash
./scripts/deploy_backend.sh --env staging
```

- The current release entrypoints are:

```bash
./scripts/deploy_backend.sh --env production
./scripts/release_testflight.sh 5.7.0 20226 --branch codex/stable-5.7 --skip-main-promotion
```

Those commands are intentionally gated by `todo.md`, the audit document, and
final CI evidence. Do not bypass them for the 5.7.0 line.

## D1 Backup And Restore Path

`scripts/deploy_backend.sh` exports a remote D1 SQL backup before it applies any
remote migrations. The export lands under `.local/build` with this shape:

```bash
.local/build/d1-<env>-backup-<timestamp>.sql
```

The deploy summary prints that backup path explicitly so it can be archived with
the release evidence.

The restore path is intentionally separate from deploys because the safe
production workflow is to restore into a replacement D1 database, not replay a
full export into the currently serving database. The supported import helper is:

```bash
./scripts/restore_backend_d1.sh --env production --file .local/build/d1-production-backup-<timestamp>.sql --database-name <replacement-db-name> --yes
```

Recommended recovery sequence:

1. create a replacement D1 database in Cloudflare
2. import the exported SQL backup into that replacement database with `scripts/restore_backend_d1.sh`
3. update `.local/backend.env` so `BACKEND_<ENV>_D1_DATABASE_NAME` and `BACKEND_<ENV>_D1_DATABASE_ID` point at the replacement database
4. redeploy the Worker with:

```bash
./scripts/deploy_backend.sh --env <staging|production> --skip-migrations
```

The import step uses Wrangler's remote D1 ingestion path:

```bash
npx wrangler d1 execute <database-name> --remote --file <backup.sql> --yes
```
