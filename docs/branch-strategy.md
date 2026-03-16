# Branch Strategy

## Long-Lived Branches

- `main`
  - default GitHub branch
  - always points to the latest released stable build
- `codex/stable-4.1`
  - frozen historical stable line
  - read-only unless a data-safety or release-blocking emergency requires a one-off patch
- `codex/stable-4.2`
  - active 4.2.x release line
  - every 4.2.x TestFlight release lands here first

## Short-Lived Branches

- `codex/feature/<topic>`
  - implementation branches only
  - branch from `codex/stable-4.2`
  - delete after the release commit lands on `codex/stable-4.2`

## Archival Policy

- Do not keep backup, beta, or fix branches alive after they have been superseded.
- Preserve historical pointers with annotated tags under:
  - `archive/default/...`
  - `archive/branch/...`
- After archive tags are pushed, delete the original branches locally and on GitHub.

## Release Alignment

- Release tags use `v<marketing-version>`.
- After a stable release succeeds on TestFlight:
  - tag the release commit
  - push `codex/stable-4.2`
  - fast-forward `main` to the same commit
  - keep `main` and `codex/stable-4.2` aligned until the next development cycle starts
