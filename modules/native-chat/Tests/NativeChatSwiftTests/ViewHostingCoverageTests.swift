import BackendContracts
import ChatDomain
import ChatPersistenceCore
import Foundation
import GeneratedFilesCore
import SnapshotTesting
import SwiftUI
import Testing
import UIKit
import XCTest
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

@MainActor
final class ViewHostingCoverageTests: XCTestCase {
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

    func testSettingsGatewaySnapshot() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        defer { try? FileManager.default.removeItem(at: harness.cacheRoot) }

        harness.client.connectionStatus = ConnectionCheckDTO(
            backend: .degraded,
            auth: .healthy,
            openaiCredential: .invalid,
            sse: .degraded,
            checkedAt: Date().addingTimeInterval(-7200),
            latencyMilliseconds: 180,
            errorSummary: "Realtime degraded"
        )
        await harness.settingsPresenter.account.checkConnection()
        await harness.settingsPresenter.credentials.refreshStatus()

        assertHostedSnapshot(
            named: "phone-light",
            testName: #function,
            size: CGSize(width: 393, height: 1200),
            delay: 0.15,
            backgroundColor: .systemGroupedBackground
        ) {
            settingsHostedSnapshotSurface {
                SettingsView(viewModel: harness.settingsPresenter)
            }
        }
    }

    func testModelSelectorSnapshot() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        defer { try? FileManager.default.removeItem(at: harness.cacheRoot) }
        let controller = harness.makeChatController()
        controller.selectedModel = .gpt5_4_pro
        controller.reasoningEffort = .xhigh
        controller.serviceTier = .flex

        assertHostedSnapshot(named: "phone-light", testName: #function, size: CGSize(width: 393, height: 680)) {
            BackendChatSelectorOverlay(viewModel: controller, selectedTheme: .light, onDismiss: {})
        }
    }

    func testChatCoverageSnapshots() throws {
        let emptyHarness = try makeNativeChatHarness(signedIn: false)
        defer { try? FileManager.default.removeItem(at: emptyHarness.cacheRoot) }
        let emptyController = emptyHarness.makeChatController()
        assertHostedSnapshot(named: "empty-phone-light", testName: #function, size: hostedSnapshotVariant.canvasSize, delay: 0.15) {
            BackendChatView(viewModel: emptyController, openSettings: {})
        }

        let overlayHarness = try makeNativeChatHarness(signedIn: true)
        defer { try? FileManager.default.removeItem(at: overlayHarness.cacheRoot) }
        let overlayController = overlayHarness.makeChatController()
        overlayController.selectedModel = .gpt5_4_pro
        overlayController.reasoningEffort = .xhigh
        overlayController.serviceTier = .flex
        assertHostedSnapshot(named: "overlay-phone-light", testName: #function, size: hostedSnapshotVariant.canvasSize, delay: 0.15) {
            BackendChatSelectorOverlay(viewModel: overlayController, selectedTheme: .light, onDismiss: {})
        }
    }

    func testDetachedStreamingSnapshot() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        defer { try? FileManager.default.removeItem(at: harness.cacheRoot) }
        let controller = harness.makeChatController()
        controller.messages = [
            makeBackendMessageSurface(
                role: .assistant,
                content: "Stored response",
                isComplete: true,
                includeTrace: true
            )
        ]
        controller.isStreaming = true
        controller.currentThinkingText = "Checking the release pipeline."
        controller.currentStreamingText = "Archive complete. Uploading the build now."
        controller.activeToolCalls = [
            ToolCallInfo(id: "ci_done", type: .codeInterpreter, status: .completed, code: "print('release ok')", results: ["release ok"])
        ]
        controller.liveCitations = [URLCitation(url: "https://example.com/release", title: "Release Checklist", startIndex: 0, endIndex: 8)]

        assertHostedSnapshot(named: "streaming-phone-light", testName: #function, size: CGSize(width: 393, height: 1000), delay: 0.15) {
            BackendChatView(viewModel: controller, openSettings: {})
        }
    }

    func testAgentSelectorSnapshot() throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        defer { try? FileManager.default.removeItem(at: harness.cacheRoot) }
        let controller = harness.makeAgentController()
        controller.flexModeEnabled = true
        controller.leaderReasoningEffort = .high
        controller.workerReasoningEffort = .medium

        assertHostedSnapshot(named: "agent-selector-phone-light", testName: #function, size: CGSize(width: 393, height: 540), delay: 0.15) {
            BackendAgentSelectorOverlay(viewModel: controller, selectedTheme: .light, onDismiss: {})
        }
    }

    func testFilePreviewSnapshots() throws {
        let imageURL = try makeSnapshotImageFile()
        assertHostedSnapshot(
            named: "image-phone-light",
            testName: #function,
            size: hostedSnapshotVariant.canvasSize,
            delay: 0.25
        ) {
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
        assertHostedSnapshot(
            named: "pdf-phone-light",
            testName: #function,
            size: hostedSnapshotVariant.canvasSize,
            delay: 0.25
        ) {
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

    func testPresentationCoverageSnapshot() {
        assertHostedSnapshot(named: "phone-light", testName: #function, size: CGSize(width: 393, height: 420)) {
            VStack(alignment: .leading, spacing: 16) {
                ThinkingView(
                    text: "First **reason** step, then confirm the release is stable.",
                    isLive: false,
                    externalIsExpanded: .constant(true)
                )
                TypingIndicator()
                CodeInterpreterIndicator()
                CodeInterpreterResultView(
                    toolCall: ToolCallInfo(
                        id: "ci_result",
                        type: .codeInterpreter,
                        status: .completed,
                        code: "print('release ok')",
                        results: ["release ok", "upload complete"]
                    )
                )
            }
            .padding()
        }
    }
}

@MainActor
private func settingsHostedSnapshotSurface(
    @ViewBuilder content: () -> some View
) -> some View {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
        content()
    }
}

private let hostedSnapshotVariant = HostedSnapshotVariant.phoneLight

private enum HostedSnapshotVariant {
    case phoneLight

    var canvasSize: CGSize {
        CGSize(width: 393, height: 852)
    }

    var safeArea: UIEdgeInsets {
        UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    var traits: UITraitCollection {
        UITraitCollection(mutations: {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = .compact
            $0.verticalSizeClass = .regular
            $0.displayScale = 3
            $0.userInterfaceStyle = .light
        })
    }

    func imageConfig(size: CGSize) -> ViewImageConfig {
        ViewImageConfig(safeArea: safeArea, size: size, traits: traits)
    }
}

@MainActor
private func assertHostedSnapshot(
    named name: String,
    testName: String,
    size: CGSize,
    delay: TimeInterval = 0,
    backgroundColor: UIColor = .clear,
    file: StaticString = #filePath,
    line: UInt = #line,
    @ViewBuilder content: () -> some View
) {
    let previousTheme = UserDefaults.standard.string(forKey: SettingsStore.Keys.appTheme)
    defer {
        if let previousTheme {
            UserDefaults.standard.set(previousTheme, forKey: SettingsStore.Keys.appTheme)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsStore.Keys.appTheme)
        }
    }

    UserDefaults.standard.set(AppTheme.light.rawValue, forKey: SettingsStore.Keys.appTheme)

    let controller = UIHostingController(
        rootView: content()
            .environment(\.hapticsEnabled, true)
            .preferredColorScheme(.light)
    )
    controller.loadViewIfNeeded()
    controller.view.backgroundColor = backgroundColor
    controller.preferredContentSize = size
    controller.view.bounds = CGRect(origin: .zero, size: size)
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()

    if delay > 0 {
        RunLoop.main.run(until: Date().addingTimeInterval(delay))
    }

    assertSnapshot(
        of: controller,
        as: .image(on: hostedSnapshotVariant.imageConfig(size: size)),
        named: name,
        file: file,
        testName: testName,
        line: line
    )
}
