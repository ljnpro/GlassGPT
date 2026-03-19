# 4.8.2 Parity Baseline

This document records the `4.7.0` production baseline that `4.8.2` must preserve.

## Stable Baseline

- source branch: `codex/stable-4.8`
- baseline branch: `codex/stable-4.7`
- development branch: `codex/feature/4.8.2-*`
- baseline app version: `4.7.0 (20179)`

## User-Visible Invariants

- three-tab structure: Chat, History, Settings
- message bubble presentation and context menus
- composer layout, attachment affordances, and stop/send behavior
- model selector presentation and controls
- file preview/share behavior
- history selection/search/delete flows
- settings sections, validation flow, and gateway controls
- streaming and recovery preserve one logical assistant reply -> one visible bubble

## Manual Acceptance

Run this checklist against `v4.7.0` and the current `4.8.2` candidate:

1. launch the app and confirm empty-shell parity
2. send a standard message and a long streaming message
3. stop generation and verify partial persistence
4. force recovery and verify final single-bubble behavior
5. toggle background mode and reopen after interruption
6. open history, select, delete one, and delete all
7. save/clear settings and validate gateway feedback
8. open generated files and verify preview/share/save behavior

## Release Gates

- `./scripts/ci.sh`
- `./scripts/ci.sh core-tests`
- `./scripts/ci.sh ui-tests`
- `./scripts/ci.sh maintainability`
- `./scripts/ci.sh source-share`
- `./scripts/ci.sh module-boundary`
- `./scripts/ci.sh release-readiness`
