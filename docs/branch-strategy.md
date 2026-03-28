# Branch Strategy

## Long-Lived Branches

- `main`
  - promotion target after a Beta 5.0 release candidate is validated
  - should point to the latest shipped product-quality line
- `stable-4.12`
  - frozen local backup of the pre-5.0 architecture
  - keep as the rollback and parity reference line
- `codex/stable-4.12`
  - GitHub mirror of the frozen pre-5.0 line when the branch is pushed remotely
- `stable-5.0`
  - optional post-cutover stable line after the first 5.0 release is published
- `codex/stable-5.0`
  - remote mirror of the 5.0 stable line once that line exists

## Active Cutover Branch

- `feature/beta-5.0-cloudflare-all-in`
  - the active local release-preparation branch for the backend-owned Beta 5.0 cutover
  - may publish internal and TestFlight release candidates before `main` promotion
- `codex/feature/beta-5.0-cloudflare-all-in`
  - remote mirror of the active Beta 5.0 cutover branch when pushed to GitHub

## Short-Lived Branches

- `feature/<topic>`
  - branch from the active release-preparation line
  - publish as `codex/feature/<topic>` if mirrored remotely
  - merge back only after local CI, release-readiness, and manual log review are clean
  - delete after the change lands

## Release Alignment

- Beta 5.0 release candidates may be published from `feature/beta-5.0-cloudflare-all-in`.
- Do not promote `main` until the 5.0 release candidate has:
  - passed `./scripts/ci.sh release-readiness`
  - passed the required hard lanes that were validated on the same tree
  - produced a clean TestFlight upload with manually reviewed logs
- Preserve `stable-4.12` / `codex/stable-4.12` as the frozen rollback line during the 5.0 rollout.
- After the first 5.0 release is accepted:
  - optionally establish `stable-5.0` / `codex/stable-5.0`
  - promote `main` to the same commit
  - keep the prior stable backup tag and source bundle
