import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import GeneratedFilesCore
import PDFKit
import SwiftUI
import Testing
import UIKit
@testable import NativeChatComposition
@testable import NativeChatUI

@MainActor
struct PresentationHelperTests {
    @Test func `message bubble prefers live assistant overrides`() {
        let message = Message(
            role: .assistant,
            content: "Stored content",
            thinking: "Stored thinking",
            annotations: [URLCitation(url: "https://stored.example", title: "Stored", startIndex: 0, endIndex: 6)],
            toolCalls: [ToolCallInfo(id: "stored", type: .webSearch, status: .completed)],
            filePathAnnotations: [
                FilePathAnnotation(
                    fileId: "file_stored",
                    containerId: "container",
                    sandboxPath: "sandbox:/tmp/stored.txt",
                    filename: "stored.txt",
                    startIndex: 0,
                    endIndex: 6
                )
            ]
        )
        let liveCitation = URLCitation(url: "https://live.example", title: "Live", startIndex: 1, endIndex: 4)
        let liveToolCall = ToolCallInfo(id: "live", type: .codeInterpreter, status: .interpreting)
        let liveFileAnnotation = FilePathAnnotation(
            fileId: "file_live",
            containerId: nil,
            sandboxPath: "sandbox:/tmp/live.txt",
            filename: "live.txt",
            startIndex: 0,
            endIndex: 4
        )
        let bubble = MessageBubble(
            message: message,
            liveContent: "Live content",
            liveThinking: "Live thinking",
            activeToolCalls: [liveToolCall],
            liveCitations: [liveCitation],
            liveFilePathAnnotations: [liveFileAnnotation],
            showsRecoveryIndicator: true
        )

        #expect(bubble.displayedContent == "Live content")
        #expect(bubble.displayedThinking == "Live thinking")
        #expect(bubble.displayedToolCalls == [liveToolCall])
        #expect(bubble.displayedCitations == [liveCitation])
        #expect(bubble.displayedFilePathAnnotations == [liveFileAnnotation])
        #expect(bubble.isDisplayingLiveAssistantState)
    }

    @Test func `message bubble ignores live state for user messages`() {
        let message = Message(role: .user, content: "Prompt")
        let bubble = MessageBubble(
            message: message,
            liveContent: "Ignored live content",
            liveThinking: "Ignored live thinking",
            activeToolCalls: [ToolCallInfo(id: "tool", type: .webSearch, status: .searching)],
            liveCitations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
            showsRecoveryIndicator: true
        )

        #expect(!bubble.isDisplayingLiveAssistantState)
        #expect(bubble.displayedContent == "Ignored live content")
    }

    @Test func `model selector metrics and short labels stay stable across idioms`() {
        let padMetrics = ModelSelectorSheet.Metrics(idiom: .pad)
        let phoneMetrics = ModelSelectorSheet.Metrics(idiom: .phone)
        let sheet = ModelSelectorSheet(
            proModeEnabled: .constant(true),
            backgroundModeEnabled: .constant(false),
            flexModeEnabled: .constant(false),
            reasoningEffort: .constant(.xhigh),
            onDone: {}
        )

        #expect(padMetrics.sheetMaxWidth == 620)
        #expect(padMetrics.reasoningColumnWidth == 280)
        #expect(phoneMetrics.sheetMaxWidth == nil)
        #expect(phoneMetrics.reasoningColumnWidth == nil)
        #expect(sheet.effortShortLabel(.none) == "Off")
        #expect(sheet.effortShortLabel(.medium) == "Med")
        #expect(sheet.effortShortLabel(.xhigh) == "Max")
    }

    @Test func `streaming text sanitiser replaces latex delimiters without touching plain text`() {
        let text = """
        Intro $$x^2$$ and \\(y\\) then \\[z\\]
        ```swift
        print(1)
        ```
        """

        let sanitised = StreamingTextView.sanitiseText(text)

        #expect(sanitised.contains("[math]"))
        #expect(!sanitised.contains("\\("))
        #expect(!sanitised.contains("\\["))
        #expect(sanitised.contains("```swift"))
        #expect(sanitised.contains("print(1)"))
    }

    @Test func `app theme color scheme mapping matches stored theme`() {
        #expect(AppTheme.system.colorScheme == nil)
        #expect(AppTheme.light.colorScheme == .light)
        #expect(AppTheme.dark.colorScheme == .dark)
    }

    @Test func `file preview sheet computes stable viewer metrics`() throws {
        let sheet = try FilePreviewSheet(
            previewItem: FilePreviewItem(
                url: makeSnapshotImageFile(),
                kind: .generatedImage,
                displayName: "Generated Chart",
                viewerFilename: "chart.png"
            )
        )

        #expect(sheet.fileURL.lastPathComponent == "snapshot-preview-image.png")
        #expect(!sheet.isPad)
        #expect(sheet.circularButtonDiameter > 0)
        #expect(sheet.closeIconSize > 0)
        #expect(sheet.actionIconSize > 0)
    }

    @Test func `load generated image preview returns unavailable for missing file`() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-generated-image.png")
        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: missingURL) {
        case .unavailable:
            #expect(true)
        default:
            Issue.record("Expected unavailable image preview")
        }
    }

    @Test func `load generated image preview rejects non image filename`() throws {
        let url = try makeSnapshotPDFFile()
        let renamed = url.deletingPathExtension().appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.copyItem(at: url, to: renamed)

        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: renamed) {
        case let .error(message):
            #expect(message == "This file is no longer recognized as an image.")
        default:
            Issue.record("Expected image filename validation failure")
        }
    }

    @Test func `load generated image preview loads valid image`() throws {
        let url = try makeSnapshotImageFile()

        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: url) {
        case let .image(payload):
            #expect(!payload.data.isEmpty)
        default:
            Issue.record("Expected valid generated image preview")
        }
    }

    @Test func `load generated PDF preview returns unavailable for missing file`() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-generated-document.pdf")
        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: missingURL) {
        case .unavailable:
            #expect(true)
        default:
            Issue.record("Expected unavailable PDF preview")
        }
    }

    @Test func `load generated PDF preview rejects non PDF filename`() throws {
        let url = try makeSnapshotImageFile()
        let renamed = url.deletingPathExtension().appendingPathExtension("png")

        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: renamed) {
        case let .error(message):
            #expect(message == "This file is no longer recognized as a PDF.")
        default:
            Issue.record("Expected PDF filename validation failure")
        }
    }

    @Test func `load generated PDF preview loads valid PDF`() throws {
        let url = try makeSnapshotPDFFile()

        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: url) {
        case let .document(document):
            #expect(document.pageCount > 0)
        default:
            Issue.record("Expected valid generated PDF preview")
        }
    }
}
