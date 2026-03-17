# Branch Strategy

## Long-Lived Branches

- `main`
  - default GitHub branch
  - always points to the latest released stable build
- `codex/stable-4.1`
  - frozen historical stable line
  - read-only unless a data-safety or release-blocking emergency requires a one-off patch
- `codex/stable-4.2`
  - maintenance branch for post-4.3 hot-fixes only
  - no feature development
- `codex/stable-4.3`
  - active 4.3.x release line
  - every 4.3.x release lands here first

## Short-Lived Branches

- `codex/feature/<topic>`
  - implementation branches only
  - branch from `codex/stable-4.3`
  - merge to `codex/stable-4.3` through PR/review only
  - delete after the release commit lands on `codex/stable-4.3`

## Archival Policy

- Do not keep backup, beta, or fix branches alive after they have been superseded.
- Preserve historical pointers with annotated tags under:
  - `archive/default/...`
  - `archive/branch/...`
- After archive tags are pushed, delete the original branches locally and on GitHub.

## Release Alignment

- Release tags use `v<marketing-version>`.
- Before a large refactor release, create an annotated backup tag and a local source bundle from the previous stable commit.
- After a stable release succeeds on TestFlight:
  - verify `scripts/ci.sh release-readiness` passes on `codex/stable-4.3`
  - tag the release commit
  - push `codex/stable-4.3`
  - fast-forward `main` to the same commit
  - keep `main` and `codex/stable-4.3` aligned until the next development cycle starts
