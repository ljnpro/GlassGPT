# 4.4.0 Parity Baseline

This document records the `4.3.1` production baseline that `4.4.0` must preserve.

## Stable Baseline

- Source branch: `codex/stable-4.3`
- Development branch: `codex/feature/4.4.0-*`
- Baseline app version: `4.3.1 (20172)`
- App target: `GlassGPT`
- Package target: `NativeChat`
- Current package size: ~14k Swift LOC across 101 Swift files

## Verified Build

Last verified baseline command:

```bash
xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'generic/platform=iOS Simulator' build
```

Baseline result before 4.4.0 work:

- Build status: succeeded
- Existing warnings:
  - `appintentsmetadataprocessor`: `Metadata extraction skipped. No AppIntents.framework dependency found.`

## User-Visible Invariants

The following must remain unchanged unless a release blocker forces a deviation:

- Three-tab structure: Chat, History, Settings
- Empty-state layout and copy
- Message bubble layout, colors, spacing, typography, and context menus
- Composer layout, attachment affordances, and stop/send behavior
- Model selector presentation and controls
- File preview presentation, interaction model, and share behavior
- History selection and deletion flows
- Settings sections, toggles, pickers, labels, and validation flow
- Streaming, recovery, and detached streaming bubble behavior
- One logical assistant reply remains one visible assistant bubble even across paragraph breaks and recovery
- Generated image/document cache behavior
- Cloudflare gateway behavior and defaults
- Keychain API key storage behavior

## Manual Acceptance Checklist

Run this checklist against both `v4.3.1` and the current `4.4.0` candidate before release:

1. Launch the app and confirm the initial empty state matches.
2. Open Settings and confirm sections, ordering, labels, and controls match.
3. Toggle theme, haptics, Cloudflare, Pro mode, Background mode, Flex mode, and confirm behavior matches.
4. Save and clear the API key and confirm the local validation flow and alerts match.
5. Enable gateway mode without a saved key and confirm the missing-key feedback matches.
6. Start a new chat and confirm toolbar layout and model badge match.
7. Send a text message and confirm user/assistant message presentation matches.
8. Send an image attachment and confirm preview and send behavior match.
9. Send a document attachment and confirm chip rendering and send behavior match.
10. While streaming, confirm indicators, stop button, and live bubble behavior match.
11. Force a recovery path and confirm recovery indicator, final output, single-bubble behavior, and error handling match.
12. Open History, search conversations, select a conversation, delete one conversation, and delete all conversations.
13. Open a generated file and confirm preview/share behavior matches.
14. Clear image/document caches and confirm settings UI and results match.

## Release Gates

- `scripts/ci.sh` passes
- `scripts/ci.sh app-tests` passes
- `scripts/ci.sh snapshot-tests` passes
- `scripts/ci.sh package-tests` passes
- `scripts/ci.sh coverage-report` passes
- `scripts/ci.sh maintainability` passes
- `scripts/ci.sh` release-readiness passes
- `xcodebuild` build passes
- grouped tests pass (`./scripts/ci.sh core-tests` / `ui-tests`)
- manual parity checklist passes
- Release archive/export succeeds
- TestFlight upload succeeds
- GitHub branch/tag push succeeds
