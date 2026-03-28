UI_TEST_CASES=(
  testTabsAndPrimaryScreensRemainReachable
  testHistorySignedOutStateCanOpenSettings
  testChatSignedOutStateCanOpenAccountAndSync
  testAgentSignedOutStateCanOpenAccountAndSync
  GlassGPTUISettingsFlowTests/testSettingsShowsAccountAndNavigationSections
  GlassGPTUISettingsFlowTests/testSettingsAgentDefaultsPersistWithinSession
  GlassGPTUISettingsFlowTests/testSettingsThemeSelectionPersistsWithinSession
  GlassGPTUISettingsFlowTests/testSettingsOpensCacheAndAboutDestinations
  GlassGPTUISettingsFlowTests/testSettingsTapOutsideDismissesAPIKeyKeyboard
  GlassGPTUISettingsFlowTests/testSettingsDragDismissesAPIKeyKeyboard
  testEmptyScenarioKeepsShellUsableWithoutSignIn
  GlassGPTUIRichScenarioTests/testRichChatScenarioShowsAssistantSurfaceAndSelector
  GlassGPTUIRichScenarioTests/testRichAgentScenarioShowsLiveSummaryAndProcessCard
  GlassGPTUIRichScenarioTests/testRichAgentSelectorScenarioShowsControls
  GlassGPTUIRichScenarioTests/testSignedInSettingsScenarioSupportsConnectionCheckAndSignOut
  GlassGPTUIRichScenarioTests/testPreviewScenarioPresentsAndDismissesPreviewSheet
  AccessibilityAuditTests/testChatTabAccessibilityAudit
  AccessibilityAuditTests/testHistoryTabAccessibilityAudit
  AccessibilityAuditTests/testAgentTabAccessibilityAudit
  AccessibilityAuditTests/testSettingsTabAccessibilityAudit
)

REINSTALL_UI_TEST_CASES=(
  testEmptyScenarioKeepsShellUsableWithoutSignIn
  GlassGPTUISettingsFlowTests/testSettingsShowsAccountAndNavigationSections
)

function resolve_ui_test_cases() {
  local filter="${1:-}"

  case "$filter" in
    "")
      printf '%s\n' "${UI_TEST_CASES[@]}"
      ;;
    shard-1|shard-2|shard-3)
      local shard_index="${filter##*-}"
      local ui_case
      local case_index=0
      for ui_case in "${UI_TEST_CASES[@]}"; do
        (( case_index += 1 ))
        if (( ((case_index - 1) % 3) + 1 == shard_index )); then
          printf '%s\n' "$ui_case"
        fi
      done
      ;;
    *)
      local -a explicit_cases=()
      IFS=',' read -ra explicit_cases <<< "$filter"
      printf '%s\n' "${explicit_cases[@]}"
      ;;
  esac
}
