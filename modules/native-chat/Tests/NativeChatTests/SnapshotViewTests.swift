import SnapshotTesting
import SwiftUI
import XCTest
@testable import NativeChat

@MainActor
final class SnapshotViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        isRecording = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        isRecording = false
        super.tearDown()
    }

    func testChatSnapshots() throws {
        let emptyViewModel = try makeSnapshotChatViewModel(hasAPIKey: false)
        assertViewSnapshots(named: "chat-empty") {
            ChatView(viewModel: emptyViewModel)
        }

        let conversationViewModel = try makeSnapshotChatViewModel(hasAPIKey: true)
        _ = makeConversationSamples(in: conversationViewModel)
        assertViewSnapshots(named: "chat-standard") {
            ChatView(viewModel: conversationViewModel)
        }

        let streamingViewModel = try makeSnapshotChatViewModel(hasAPIKey: true)
        _ = makeConversationSamples(in: streamingViewModel)
        streamingViewModel.isStreaming = true
        streamingViewModel.isThinking = true
        streamingViewModel.currentThinkingText = "Gathering the deployment steps before finalizing the answer."
        streamingViewModel.currentStreamingText = "The release pipeline is running and the archive has completed successfully."
        streamingViewModel.activeToolCalls = [
            ToolCallInfo(
                id: "ci_1",
                type: .codeInterpreter,
                status: .interpreting,
                code: "print('build ok')",
                results: ["build ok"]
            )
        ]
        assertViewSnapshots(named: "chat-streaming") {
            ChatView(viewModel: streamingViewModel)
        }

        let errorViewModel = try makeSnapshotChatViewModel(hasAPIKey: true)
        _ = makeConversationSamples(in: errorViewModel)
        errorViewModel.errorMessage = "Connection lost. Please check your network and try again."
        assertViewSnapshots(named: "chat-error") {
            ChatView(viewModel: errorViewModel)
        }
    }

    func testHistorySnapshots() throws {
        let container = try makeHistorySnapshotContainer()
        assertViewSnapshots(named: "history-list") {
            HistoryView()
                .modelContainer(container)
        }
    }

    func testSettingsSnapshots() {
        let viewModel = makeSettingsSnapshotViewModel()
        assertViewSnapshots(named: "settings") {
            SettingsView(viewModel: viewModel)
        }
    }

    func testModelSelectorSnapshots() {
        assertViewSnapshots(named: "model-selector") {
            SnapshotModelSelectorHost()
        }
    }

    func testFilePreviewSnapshots() throws {
        let imageURL = try makeSnapshotImageFile()
        assertViewSnapshots(named: "file-preview-image", delay: 0.25) {
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
        assertViewSnapshots(named: "file-preview-pdf", delay: 0.25) {
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
}

private struct SnapshotModelSelectorHost: View {
    @State private var configuration = ConversationConfiguration(
        model: .gpt5_4_pro,
        reasoningEffort: .xhigh,
        backgroundModeEnabled: true,
        serviceTier: .flex
    )

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()

            ModelSelectorSheet(
                proModeEnabled: Binding(
                    get: { configuration.proModeEnabled },
                    set: { configuration.proModeEnabled = $0 }
                ),
                backgroundModeEnabled: $configuration.backgroundModeEnabled,
                flexModeEnabled: Binding(
                    get: { configuration.flexModeEnabled },
                    set: { configuration.flexModeEnabled = $0 }
                ),
                reasoningEffort: $configuration.reasoningEffort,
                onDone: {}
            )
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
    }
}
