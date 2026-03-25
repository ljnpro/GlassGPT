import ChatDomain
import ChatPersistenceSwiftData
import SwiftUI
@testable import NativeChatComposition
@testable import NativeChatUI

@MainActor
extension SnapshotViewTests {
    func assertChatEmptySnapshot() throws {
        let emptyViewModel = try makeSnapshotChatScreenStore(hasAPIKey: false)
        assertViewSnapshots(
            named: "chat-empty",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: emptyViewModel)
        }
    }

    func assertChatStandardSnapshot() throws {
        let conversationViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: conversationViewModel)
        conversationViewModel.selectedModel = .gpt5_4_pro
        conversationViewModel.reasoningEffort = .xhigh
        conversationViewModel.backgroundModeEnabled = true
        conversationViewModel.serviceTier = .flex
        assertViewSnapshots(
            named: "chat-standard",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: conversationViewModel)
        }
    }

    func assertChatRichMarkdownSnapshot() throws {
        let richMarkdownViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeRichMarkdownConversationSamples(in: richMarkdownViewModel)
        assertViewSnapshots(
            named: "chat-rich-assistant-response",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: richMarkdownViewModel)
        }
    }

    func assertChatCodeBlockSnapshot() throws {
        let codeBlockViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeRichMarkdownCodeBlockConversationSamples(in: codeBlockViewModel)
        assertViewSnapshots(
            named: "chat-rich-assistant-response-code-block",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: codeBlockViewModel)
        }
    }

    func assertChatTableSnapshot() throws {
        let tableViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeRichMarkdownTableConversationSamples(in: tableViewModel)
        assertViewSnapshots(
            named: "chat-rich-assistant-response-table",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: tableViewModel)
        }
    }

    func assertChatStreamingSnapshot() throws {
        let streamingViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: streamingViewModel)
        streamingViewModel.isStreaming = true
        streamingViewModel.isThinking = true
        streamingViewModel.thinkingPresentationState = .reasoning
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
        assertViewSnapshots(
            named: "chat-streaming",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: streamingViewModel)
        }
    }

    func assertChatErrorSnapshot() throws {
        let errorViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: errorViewModel)
        errorViewModel.errorMessage = "Connection lost. Please check your network and try again."
        assertViewSnapshots(
            named: "chat-error",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: errorViewModel)
        }
    }

    func assertChatRestoringSnapshot() throws {
        let restoringViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: restoringViewModel)
        restoringViewModel.isRestoringConversation = true
        assertViewSnapshots(
            named: "chat-restoring",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: restoringViewModel)
        }
    }

    func assertChatRecoveringSnapshot() throws {
        let recoveringViewModel = try makeSnapshotChatScreenStore(hasAPIKey: true)
        _ = makeConversationSamples(in: recoveringViewModel)
        if let liveDraft = recoveringViewModel.messages.last {
            recoveringViewModel.visibleSessionMessageID = liveDraft.id
            recoveringViewModel.draftMessage = liveDraft
        }
        recoveringViewModel.isStreaming = true
        recoveringViewModel.isRecovering = true
        recoveringViewModel.thinkingPresentationState = .waiting
        recoveringViewModel.currentThinkingText = "Rebinding the in-progress response after app relaunch."
        recoveringViewModel.currentStreamingText = "Recovery stream connected. Replaying any missing deltas now."
        assertViewSnapshots(
            named: "chat-recovering",
            file: snapshotViewTestsFilePath,
            testName: "testChatSnapshots()"
        ) {
            ChatView(viewModel: recoveringViewModel)
        }
    }

    func assertThinkingViewSnapshot() {
        assertViewSnapshots(
            named: "thinking-view",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            ThinkingView(
                text: "First **reason** step.\n\nThen evaluate `x^2` and finish.",
                isLive: false,
                externalIsExpanded: .constant(true)
            )
        }
    }

    func assertThinkingIndicatorSnapshot() {
        assertViewSnapshots(
            named: "thinking-indicator",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            ThinkingIndicator()
                .padding()
        }
    }

    func assertCodeBlockSnapshot() {
        assertViewSnapshots(
            named: "code-block",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            CodeBlockView(
                language: "swift",
                code: """
                struct BuildReport {
                    let version: String
                    let passed: Bool
                }
                """,
                surfaceStyle: .standalone
            )
        }
    }

    func assertCodeInterpreterIndicatorSnapshot() {
        assertViewSnapshots(
            named: "code-interpreter-indicator",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            CodeInterpreterIndicator()
                .padding()
        }
    }

    func assertCodeInterpreterResultSnapshot() {
        assertViewSnapshots(
            named: "code-interpreter-result",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            CodeInterpreterResultView(
                toolCall: ToolCallInfo(
                    id: "ci_result",
                    type: .codeInterpreter,
                    status: .completed,
                    code: "print('release ok')",
                    results: ["release ok", "archive complete"]
                )
            )
            .padding()
        }
    }

    func assertFileAttachmentsRowSnapshot() {
        assertViewSnapshots(
            named: "file-attachments-row",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            FileAttachmentsRow(
                attachments: [
                    FileAttachment(
                        filename: "report.pdf",
                        fileSize: 12800,
                        fileType: "pdf",
                        uploadStatus: .uploaded
                    ),
                    FileAttachment(
                        filename: "chart.png",
                        fileSize: 8192,
                        fileType: "png",
                        uploadStatus: .uploading
                    ),
                    FileAttachment(
                        filename: "trace.txt",
                        fileSize: 256,
                        fileType: "txt",
                        uploadStatus: .failed
                    )
                ]
            )
            .padding()
        }
    }

    func assertCitationLinksSnapshot() {
        assertViewSnapshots(
            named: "citation-links",
            variants: [.phoneLight, .phoneDark],
            file: snapshotViewTestsFilePath,
            testName: "testPresentationComponentSnapshots()"
        ) {
            CitationLinksView(
                citations: [
                    URLCitation(
                        url: "https://example.com/one",
                        title: "Release Notes",
                        startIndex: 0,
                        endIndex: 10
                    ),
                    URLCitation(
                        url: "https://example.com/two",
                        title: "Architecture Review",
                        startIndex: 11,
                        endIndex: 20
                    )
                ]
            )
            .padding()
        }
    }
}
