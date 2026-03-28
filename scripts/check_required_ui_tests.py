#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REQUIRED_UI_TESTS = (
    "GlassGPTUITests/testTabsAndPrimaryScreensRemainReachable()",
    "GlassGPTUITests/testHistorySignedOutStateCanOpenSettings()",
    "GlassGPTUITests/testChatSignedOutStateCanOpenAccountAndSync()",
    "GlassGPTUITests/testAgentSignedOutStateCanOpenAccountAndSync()",
    "GlassGPTUISettingsFlowTests/testSettingsShowsAccountAndNavigationSections()",
    "GlassGPTUISettingsFlowTests/testSettingsAgentDefaultsPersistWithinSession()",
    "GlassGPTUISettingsFlowTests/testSettingsThemeSelectionPersistsWithinSession()",
    "GlassGPTUISettingsFlowTests/testSettingsOpensCacheAndAboutDestinations()",
    "GlassGPTUISettingsFlowTests/testSettingsTapOutsideDismissesAPIKeyKeyboard()",
    "GlassGPTUISettingsFlowTests/testSettingsDragDismissesAPIKeyKeyboard()",
    "GlassGPTUITests/testEmptyScenarioKeepsShellUsableWithoutSignIn()",
    "GlassGPTUIRichScenarioTests/testRichChatScenarioShowsAssistantSurfaceAndSelector()",
    "GlassGPTUIRichScenarioTests/testRichAgentScenarioShowsLiveSummaryAndProcessCard()",
    "GlassGPTUIRichScenarioTests/testRichAgentSelectorScenarioShowsControls()",
    "GlassGPTUIRichScenarioTests/testSignedInSettingsScenarioSupportsConnectionCheckAndSignOut()",
    "GlassGPTUIRichScenarioTests/testPreviewScenarioPresentsAndDismissesPreviewSheet()",
    "AccessibilityAuditTests/testChatTabAccessibilityAudit()",
    "AccessibilityAuditTests/testHistoryTabAccessibilityAudit()",
    "AccessibilityAuditTests/testAgentTabAccessibilityAudit()",
    "AccessibilityAuditTests/testSettingsTabAccessibilityAudit()",
)


def load_tests(xcresult: Path) -> dict[str, str]:
    completed = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "tests",
            "--path",
            str(xcresult),
            "--format",
            "json",
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or f"failed to inspect {xcresult}")

    payload = json.loads(completed.stdout)
    collected: dict[str, str] = {}

    def visit(node: dict[str, object]) -> None:
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier")
            result = node.get("result")
            if isinstance(identifier, str) and isinstance(result, str):
                previous = collected.get(identifier)
                if previous != "Passed":
                    collected[identifier] = result

        for child in node.get("children", []) or []:
            if isinstance(child, dict):
                visit(child)

    for node in payload.get("testNodes", []) or []:
        if isinstance(node, dict):
            visit(node)

    return collected


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: check_required_ui_tests.py <xcresult> [...]", file=sys.stderr)
        return 1

    xcresults = [Path(argument) for argument in argv[1:]]
    observed: dict[str, str] = {}
    for xcresult in xcresults:
        if xcresult.suffix != ".xcresult" or not xcresult.exists():
            continue
        for identifier, result in load_tests(xcresult).items():
            if identifier not in observed or observed[identifier] != "Passed":
                observed[identifier] = result

    missing = [identifier for identifier in REQUIRED_UI_TESTS if observed.get(identifier) != "Passed"]
    if missing:
        print("required UI tests missing or not passed:", file=sys.stderr)
        for identifier in missing:
            print(f"  - {identifier} (observed: {observed.get(identifier, 'missing')})", file=sys.stderr)
        return 1

    print(f"Required UI suite integrity passed for {len(REQUIRED_UI_TESTS)} test cases.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
