# Branch Strategy

## Long-Lived Branches

- `main`
  - always points to the latest released stable build
- `codex/stable-4.1`
  - frozen historical line
- `codex/stable-4.2`
  - frozen historical line
- `codex/stable-4.3`
  - frozen historical line
- `codex/stable-4.4`
  - frozen historical line
- `codex/stable-4.5`
  - frozen pre-4.6 baseline
- `codex/stable-4.6`
  - frozen pre-4.7 baseline
- `codex/stable-4.7`
  - frozen pre-4.8 baseline
- `codex/stable-4.8`
  - frozen pre-4.9 baseline
- `codex/stable-4.9`
  - active stable release line

## Short-Lived Branches

- `codex/feature/<topic>`
  - branch from `codex/stable-4.9`
  - merge back to `codex/stable-4.9` through review
  - delete after the release commit lands

## Release Alignment

- release tags use `v<marketing-version>`
- keep the `v4.8.2-backup-before-4.9.0` backup tag and source bundle
- after TestFlight publication:
  - verify `./scripts/ci.sh release-readiness` on `codex/stable-4.9`
  - verify `./scripts/ci.sh maintainability` on `codex/stable-4.9`
  - push `codex/stable-4.9`
  - fast-forward `main` to the same commit
