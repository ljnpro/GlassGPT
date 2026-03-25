# 4.12.0 Parity Baseline

This document records the `4.11.1` production baseline that `4.12.0` must preserve.

## Stable Baseline

- source branch: `stable-4.12`
- baseline branch: `codex/stable-4.11`
- development branch: `feature/4.12.0-*`
- baseline app version: `4.11.1 (20198)`

## User-Visible Invariants

- four-tab structure: Chat, Agent, History, Settings
- message bubble presentation and context menus
- composer layout, attachment affordances, and stop/send behavior
- model selector presentation and controls
- file preview/share behavior
- history selection/search/delete flows
- settings sections, validation flow, and gateway controls
- streaming and recovery preserve one logical assistant reply -> one visible bubble
- Agent mode stays isolated from Chat while Agent conversations remain visible in unified History

## Manual Acceptance

Run this checklist against the `4.11.1 (20198)` production build and the current `4.12.0` candidate:

1. launch the app and confirm empty-shell parity
2. send a standard message and a long streaming message
3. stop generation and verify partial persistence
4. force recovery and verify final single-bubble behavior
5. toggle background mode and reopen after interruption
6. open history, select, delete one, and delete all
7. save/clear settings and validate gateway feedback
8. open generated files and verify preview/share/save behavior
9. enter Agent mode, verify council progress UI, and confirm Agent history rows reopen in Agent mode

## Release Gates

- `./scripts/ci.sh`
- `./scripts/score_4_8_1.sh`
- `./scripts/score_4_8_2.sh`
- `./scripts/ci.sh core-tests`
- `./scripts/ci.sh ui-tests`
- `./scripts/ci.sh release-readiness`
