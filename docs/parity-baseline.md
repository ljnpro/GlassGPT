# 4.2.4 Parity Baseline

This document records the `4.2.3` release baseline that `4.2.4` must preserve.

## Stable Baseline

- Source branch: `codex/stable-4.2`
- Development branch: `codex/feature/4.2.4-maintainability`
- Baseline app version: `4.2.3 (20169)`
- App target: `GlassGPT`
- Package target: `NativeChat`
- Current package size: ~14k Swift LOC across 101 Swift files

## Verified Build

Last verified baseline command:

```bash
xcodebuild -project ios/GlassGPT.xcodeproj -scheme GlassGPT -destination 'generic/platform=iOS Simulator' build
```

Baseline result before 4.2.4 work:

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

Run this checklist against both `v4.2.3` and the current `4.2.4` candidate before release:

1. Launch the app and confirm the initial empty state matches.
2. Open Settings and confirm sections, ordering, labels, and controls match.
3. Toggle theme, haptics, Cloudflare, Pro mode, Background mode, Flex mode, and confirm behavior matches.
4. Start a new chat and confirm toolbar layout and model badge match.
5. Send a text message and confirm user/assistant message presentation matches.
6. Send an image attachment and confirm preview and send behavior match.
7. Send a document attachment and confirm chip rendering and send behavior match.
8. While streaming, confirm indicators, stop button, and live bubble behavior match.
9. Force a recovery path and confirm recovery indicator, final output, single-bubble behavior, and error handling match.
10. Open History, select a conversation, delete one conversation, and delete all conversations.
11. Open a generated file and confirm preview/share behavior matches.
12. Clear image/document caches and confirm settings UI and results match.

## Release Gates

- `scripts/ci.sh` passes
- `xcodebuild` build passes
- package tests pass
- manual parity checklist passes
- Release archive/export succeeds
- TestFlight upload succeeds
- GitHub branch/tag push succeeds
