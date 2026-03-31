# 5.6.0 Product Baseline

This document records the `5.4.0` production baseline that the `5.6.0`
release must preserve where behavior is intentionally continuous, while also
validating the backend-proxied attachment, tool-call, and generated-file
restorations required for `5.6.0`.

## Baseline References

- active release line: `codex/stable-5.6`
- frozen rollback branch: `stable-4.12`
- baseline app version: `5.4.0`
- candidate app version: `5.6.0`

## Preserved User-Facing Invariants

- four-tab shell remains: Chat, Agent, History, Settings
- message bubble presentation, markdown rendering, and attachment affordances remain polished and stable
- model and reasoning controls remain available from the chat and agent entry surfaces
- history selection and reopen flows remain fast and predictable
- file preview, export, and share flows remain available
- Agent mode remains visually and behaviorally distinct from Chat mode
- the app remains native SwiftUI/UIKit with no web shell takeover

## 5.6.0 Release-Quality Requirements

- backend conversation configuration is authoritative and reflected across devices
- Sign in with Apple, encrypted backend API-key custody, and same-account sync remain intact
- 250 ms polling, retry behavior, and release-readiness gates remain intact
- image upload, document upload, tool-call indicators, and generated file handling must match the shipped 4.12.6 user experience
- staged and production backend release paths exist with backup/export, smoke checks, and rollback behavior
- the release tree must satisfy the final rubric score thresholds before any backend/TestFlight publication

## Release Gates

- `./scripts/ci.sh contracts`
- `./scripts/ci.sh backend`
- `./scripts/ci.sh ios`
- `./scripts/ci.sh release-readiness`
