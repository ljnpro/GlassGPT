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
  - frozen pre-4.10 baseline
- `codex/stable-4.10`
  - frozen pre-4.11 baseline
- `codex/stable-4.11`
  - frozen pre-4.12 baseline
- `stable-4.12`
  - active local stable release line
  - publish as `codex/stable-4.12` when mirroring to GitHub

## Short-Lived Branches

- `feature/<topic>`
  - branch from `stable-4.12`
  - publish as `codex/feature/<topic>` if the branch is mirrored to GitHub
  - merge back to `stable-4.12` through review
  - delete after the release commit lands

## Release Alignment

- release tags use `v<marketing-version>`
- keep the prior stable backup tag and source bundle
- after TestFlight publication:
  - verify `./scripts/ci.sh release-readiness` on `stable-4.12`
  - verify `./scripts/ci.sh maintainability` on `stable-4.12`
  - preserve the previous `main` tip on `codex/stable-4.11` before a non-fast-forward promotion
  - push `codex/stable-4.12` when the GitHub phase begins
  - promote `main` to the same commit
