# 5.0.0 Product Baseline

This document records the `4.12.6 (20205)` production baseline that the first
`5.0.0` release must preserve where behavior is intentionally continuous, while
also validating the new backend-owned features that define Beta 5.0.

## Baseline References

- source branch: `feature/beta-5.0-cloudflare-all-in`
- frozen rollback branch: `stable-4.12`
- baseline app version: `4.12.6 (20205)`
- candidate app version: `5.0.0`

## Preserved User-Facing Invariants

- four-tab shell remains: Chat, Agent, History, Settings
- message bubble presentation, markdown rendering, and attachment affordances remain polished and stable
- model and reasoning controls remain available from the chat and agent entry surfaces
- history selection and reopen flows remain fast and predictable
- file preview, export, and share flows remain available
- Agent mode remains visually and behaviorally distinct from Chat mode
- the app remains native SwiftUI/UIKit with no web shell takeover

## New 5.0 User-Facing Requirements

- all execution continuity is backend-owned
- `Sign in with Apple` is visible in Settings and required before server-backed actions
- the user enters their own OpenAI API key in the client
- the backend stores that API key in encrypted form and the client does not retain the raw key after submission
- same-account cloud sync restores conversations, runs, and progress across relaunch and device switch
- there is no Cloudflare gateway surface in Settings
- there is no `Background Mode` toggle anywhere in the product

## Manual Acceptance

Run this checklist against the `4.12.6 (20205)` production build and the current
`5.0.0` candidate:

1. launch the app and confirm shell polish, tab reachability, and empty-state quality
2. sign in with Apple from Settings and confirm account state appears immediately
3. save a valid OpenAI API key from the client and verify `Check Connection` reports healthy
4. send a standard chat turn and verify streaming/projection quality
5. force-quit during an in-flight chat turn, relaunch, and confirm continuity without local recovery artifacts
6. start an Agent run, exit mid-stage, relaunch, and confirm server-driven progress resumes correctly
7. open History and verify synced chat and agent items reopen in the correct mode
8. open generated or cached files and verify preview/share behavior remains intact
9. sign out and verify local account-scoped state clears without cross-account leakage
10. sign back in and confirm cloud state repopulates from the backend
11. verify Settings no longer contains Cloudflare gateway or background-mode controls
12. verify the overall interaction quality feels product-grade, not like a migration shell

## Release Gates

- `./scripts/ci.sh contracts`
- `./scripts/ci.sh backend`
- `./scripts/ci.sh ios`
- `./scripts/ci.sh release-readiness`
