# Branch Strategy

## Long-Lived Branches

- `main`
  - promotion target after a `5.3.x` release is validated
  - should point to the latest shipped product-quality line
- `stable-4.12`
  - frozen local backup of the pre-backend architecture
  - keep as the rollback and parity reference line
- `codex/stable-4.12`
  - GitHub mirror of the frozen pre-backend line when pushed remotely
- `codex/stable-5.3`
  - active `5.3` release line
  - default base for `5.3.x` hardening and release-preparation work

## Active Release Work

- `feature/release-5.3-*`
  - local release-preparation or hardening branches that stack on `codex/stable-5.3`
- `codex/feature/release-5.3-*`
  - remote mirrors of `5.3` release-preparation branches when pushed to GitHub

## Short-Lived Branches

- `feature/<topic>`
  - branch from the active `5.3` release line unless a different release line is explicitly intended
  - publish as `codex/feature/<topic>` if mirrored remotely
  - merge back only after local CI, release-readiness, and manual log review are clean
  - delete after the change lands

## Release Alignment

- `5.3.x` release candidates should be prepared from `codex/stable-5.3` or a
  `feature/release-5.3-*` branch cut from it.
- Do not promote `main` until the `5.3` candidate has:
  - passed `./scripts/ci.sh release-readiness`
  - passed the required hard lanes on the same tree
  - produced the required final audit and perfect-log CI evidence
- Preserve `stable-4.12` / `codex/stable-4.12` as the frozen rollback line
  during the `5.3` rollout.
