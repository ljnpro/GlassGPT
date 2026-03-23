# 4.11.0 Parity Baseline

This document records the `4.10.9` production baseline that `4.11.0` must preserve.

## Stable Baseline

- source branch: `codex/stable-4.11`
- baseline branch: `codex/stable-4.10`
- development branch: `codex/feature/4.11.0-*`
- baseline app version: `4.10.9 (20196)`

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

Run this checklist against the `4.10.9 (20196)` production build and the current `4.11.0` candidate:

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
- `./scripts/score_4_8_1.sh`
- `./scripts/score_4_8_2.sh`
- `./scripts/ci.sh core-tests`
- `./scripts/ci.sh ui-tests`
- `./scripts/ci.sh release-readiness`
