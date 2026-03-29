import BackendContracts
import ChatDomain
import GeneratedFilesCore
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

private let snapshotViewTestsFilePath: StaticString = #filePath

@MainActor
final class SnapshotViewTests: XCTestCase {
    override func invokeTest() {
        let recordMode: SnapshotTestingConfiguration.Record =
            ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? .all : .missing
        withSnapshotTesting(record: recordMode) {
            super.invokeTest()
        }
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(false)
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            UIView.setAnimationsEnabled(true)
        }
        super.tearDown()
    }

    func testChatSnapshots() throws {
        let emptyHarness = try makeSnapshotHarness(signedIn: false)
        defer { cleanupSnapshotHarness(emptyHarness) }
        let emptyController = emptyHarness.makeChatController()
        assertViewSnapshots(named: "chat-empty", file: snapshotViewTestsFilePath, testName: #function) {
            BackendChatView(viewModel: emptyController, openSettings: {})
        }

        let standardHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(standardHarness) }
        let standardController = standardHarness.makeChatController()
        standardController.messages = [
            makeSnapshotMessageSurface(role: .user, content: "Can we ship 5.3.0 today?"),
            makeSnapshotMessageSurface(role: .assistant, content: "Yes, after the final CI and staged deploy smoke checks.")
        ]
        standardController.selectedModel = .gpt5_4_pro
        standardController.reasoningEffort = .xhigh
        standardController.serviceTier = .flex
        assertViewSnapshots(named: "chat-standard", file: snapshotViewTestsFilePath, testName: #function) {
            BackendChatView(viewModel: standardController, openSettings: {})
        }

        let streamingHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(streamingHarness) }
        let streamingController = streamingHarness.makeChatController()
        streamingController.messages = standardController.messages
        streamingController.isStreaming = true
        streamingController.isThinking = true
        streamingController.currentThinkingText = "Checking the final release gates before publish."
        streamingController.currentStreamingText = "The staged backend deployment passed health checks."
        streamingController.activeToolCalls = [
            ToolCallInfo(id: "ci_live", type: .codeInterpreter, status: .interpreting, code: "print('ok')")
        ]
        assertViewSnapshots(named: "chat-streaming", file: snapshotViewTestsFilePath, testName: #function) {
            BackendChatView(viewModel: streamingController, openSettings: {})
        }

        let errorHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(errorHarness) }
        let errorController = errorHarness.makeChatController()
        errorController.messages = standardController.messages
        errorController.errorMessage = "Connection lost while verifying release readiness."
        assertViewSnapshots(named: "chat-error", file: snapshotViewTestsFilePath, testName: #function) {
            BackendChatView(viewModel: errorController, openSettings: {})
        }

        let recoveringHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(recoveringHarness) }
        let recoveringController = recoveringHarness.makeChatController()
        recoveringController.messages = standardController.messages
        recoveringController.isStreaming = true
        recoveringController.currentThinkingText = "Rebinding the in-flight response after reconnect."
        recoveringController.currentStreamingText = "Replay connected. Applying missed deltas now."
        assertViewSnapshots(named: "chat-recovering", file: snapshotViewTestsFilePath, testName: #function) {
            BackendChatView(viewModel: recoveringController, openSettings: {})
        }
    }

    func testAgentSnapshots() throws {
        let emptyHarness = try makeSnapshotHarness(signedIn: false)
        defer { cleanupSnapshotHarness(emptyHarness) }
        let emptyController = emptyHarness.makeAgentController()
        assertViewSnapshots(named: "agent-empty", file: snapshotViewTestsFilePath, testName: #function) {
            BackendAgentView(viewModel: emptyController, openSettings: {})
        }

        let runningHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(runningHarness) }
        let runningController = runningHarness.makeAgentController()
        runningController.messages = [makeSnapshotMessageSurface(role: .assistant, content: "Synthesizing launch plan", isComplete: false)]
        runningController.isRunning = true
        runningController.isThinking = true
        runningController.currentStreamingText = "Publishing the rollout checklist."
        runningController.currentThinkingText = "Comparing staged and production smoke-check output."
        runningController.leaderReasoningEffort = .xhigh
        runningController.workerReasoningEffort = .medium
        runningController.serviceTier = .flex
        runningController.processSnapshot = AgentProcessSnapshot(
            activity: .reviewing,
            currentFocus: "Validate release evidence",
            leaderAcceptedFocus: "Validate release evidence",
            leaderLiveStatus: "Leader review",
            leaderLiveSummary: "Workers are consolidating the final release blockers."
        )
        assertViewSnapshots(named: "agent-running", file: snapshotViewTestsFilePath, testName: #function) {
            BackendAgentView(viewModel: runningController, openSettings: {})
        }

        let completedHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(completedHarness) }
        let completedController = completedHarness.makeAgentController()
        completedController.messages = [
            makeSnapshotMessageSurface(role: .user, content: "What is left before launch?"),
            makeSnapshotMessageSurface(
                role: .assistant,
                content: "Only final CI, staged smoke checks, and TestFlight publish remain.",
                includeTrace: true
            )
        ]
        completedController.processSnapshot = AgentProcessSnapshot(
            activity: .completed,
            currentFocus: "Launch complete",
            leaderAcceptedFocus: "Launch complete",
            leaderLiveStatus: "Completed",
            leaderLiveSummary: "Every release gate passed.",
            outcome: "Completed"
        )
        assertViewSnapshots(named: "agent-completed", file: snapshotViewTestsFilePath, testName: #function) {
            BackendAgentView(viewModel: completedController, openSettings: {})
        }
    }

    func testHistorySnapshots() {
        let presenter = makeSnapshotHistoryPresenter()
        assertViewSnapshots(named: "history-list", file: snapshotViewTestsFilePath, testName: #function) {
            HistoryView(store: presenter)
        }
    }

    func testSettingsSnapshots() async throws {
        let baseHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(baseHarness) }
        baseHarness.settingsPresenter.defaults.defaultProModeEnabled = true
        baseHarness.settingsPresenter.defaults.defaultFlexModeEnabled = true
        baseHarness.settingsPresenter.defaults.defaultEffort = .high
        baseHarness.settingsPresenter.agentDefaults.defaultFlexModeEnabled = true
        baseHarness.settingsPresenter.agentDefaults.defaultLeaderEffort = .xhigh
        baseHarness.settingsPresenter.agentDefaults.defaultWorkerEffort = .medium
        baseHarness.client.connectionStatus = ConnectionCheckDTO(
            backend: .healthy,
            auth: .healthy,
            openaiCredential: .healthy,
            sse: .healthy,
            checkedAt: Date().addingTimeInterval(-7200),
            latencyMilliseconds: 18,
            errorSummary: nil
        )
        await baseHarness.settingsPresenter.account.checkConnection()
        await baseHarness.settingsPresenter.credentials.refreshStatus()
        assertViewSnapshots(
            named: "settings",
            backgroundColor: .systemGroupedBackground,
            file: snapshotViewTestsFilePath,
            testName: #function
        ) {
            settingsSnapshotSurface {
                SettingsView(viewModel: baseHarness.settingsPresenter)
            }
        }

        let degradedHarness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(degradedHarness) }
        degradedHarness.client.connectionStatus = ConnectionCheckDTO(
            backend: .degraded,
            auth: .healthy,
            openaiCredential: .invalid,
            sse: .degraded,
            checkedAt: Date().addingTimeInterval(-7200),
            latencyMilliseconds: 240,
            errorSummary: "Realtime lag detected"
        )
        degradedHarness.settingsPresenter.cache.generatedImageCacheSizeBytes = 12800
        degradedHarness.settingsPresenter.cache.generatedDocumentCacheSizeBytes = 65536
        await degradedHarness.settingsPresenter.account.checkConnection()
        await degradedHarness.settingsPresenter.credentials.refreshStatus()
        assertViewSnapshots(
            named: "settings-degraded",
            backgroundColor: .systemGroupedBackground,
            file: snapshotViewTestsFilePath,
            testName: #function
        ) {
            settingsSnapshotSurface {
                SettingsView(viewModel: degradedHarness.settingsPresenter)
            }
        }
    }

    func testModelSelectorPhoneLightSnapshot() throws {
        try assertModelSelectorSnapshot(variant: .phoneLight, testName: #function)
    }

    func testModelSelectorPhoneDarkSnapshot() throws {
        try assertModelSelectorSnapshot(variant: .phoneDark, testName: #function)
    }

    func testModelSelectorPadLightSnapshot() throws {
        try assertModelSelectorSnapshot(variant: .padLight, testName: #function)
    }

    func testModelSelectorPadDarkSnapshot() throws {
        try assertModelSelectorSnapshot(variant: .padDark, testName: #function)
    }

    func testFilePreviewSnapshots() throws {
        let imageURL = try makeSnapshotImageFile()
        assertViewSnapshots(named: "file-preview-image", delay: 0.25, file: snapshotViewTestsFilePath, testName: #function) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: imageURL,
                    kind: .generatedImage,
                    displayName: "Generated Chart",
                    viewerFilename: "chart.png"
                )
            )
        }

        let pdfURL = try makeSnapshotPDFFile()
        assertViewSnapshots(named: "file-preview-pdf", delay: 0.25, file: snapshotViewTestsFilePath, testName: #function) {
            FilePreviewSheet(
                previewItem: FilePreviewItem(
                    url: pdfURL,
                    kind: .generatedPDF,
                    displayName: "Quarterly Report",
                    viewerFilename: "report.pdf"
                )
            )
        }
    }

    private func assertModelSelectorSnapshot(
        variant: SnapshotTestThemeVariant,
        testName: String
    ) throws {
        let harness = try makeSnapshotHarness(signedIn: true)
        defer { cleanupSnapshotHarness(harness) }
        let controller = harness.makeChatController()
        controller.selectedModel = .gpt5_4_pro
        controller.reasoningEffort = .xhigh
        controller.serviceTier = .flex
        assertViewSnapshots(
            named: "model-selector",
            variants: [variant],
            file: snapshotViewTestsFilePath,
            testName: testName
        ) {
            BackendChatSelectorOverlay(
                viewModel: controller,
                selectedTheme: variant.appTheme,
                onDismiss: {}
            )
        }
    }
}

@MainActor
private func settingsSnapshotSurface(
    @ViewBuilder content: () -> some View
) -> some View {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
        content()
    }
}
