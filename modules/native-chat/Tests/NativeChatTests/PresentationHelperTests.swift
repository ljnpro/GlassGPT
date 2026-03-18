import SwiftUI
import ChatDomain
import ChatPersistenceSwiftData
import GeneratedFilesCore
import PDFKit
import UIKit
import XCTest
@testable import NativeChatComposition
@testable import NativeChatUI

@MainActor
final class PresentationHelperTests: XCTestCase {
    func testMessageBubblePrefersLiveAssistantOverrides() {
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

        XCTAssertEqual(bubble.displayedContent, "Live content")
        XCTAssertEqual(bubble.displayedThinking, "Live thinking")
        XCTAssertEqual(bubble.displayedToolCalls, [liveToolCall])
        XCTAssertEqual(bubble.displayedCitations, [liveCitation])
        XCTAssertEqual(bubble.displayedFilePathAnnotations, [liveFileAnnotation])
        XCTAssertTrue(bubble.isDisplayingLiveAssistantState)
    }

    func testMessageBubbleIgnoresLiveStateForUserMessages() {
        let message = Message(role: .user, content: "Prompt")
        let bubble = MessageBubble(
            message: message,
            liveContent: "Ignored live content",
            liveThinking: "Ignored live thinking",
            activeToolCalls: [ToolCallInfo(id: "tool", type: .webSearch, status: .searching)],
            liveCitations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
            showsRecoveryIndicator: true
        )

        XCTAssertFalse(bubble.isDisplayingLiveAssistantState)
        XCTAssertEqual(bubble.displayedContent, "Ignored live content")
    }

    func testModelSelectorMetricsAndShortLabelsStayStableAcrossIdioms() {
        let padMetrics = ModelSelectorSheet.Metrics(idiom: .pad)
        let phoneMetrics = ModelSelectorSheet.Metrics(idiom: .phone)
        let sheet = ModelSelectorSheet(
            proModeEnabled: .constant(true),
            backgroundModeEnabled: .constant(false),
            flexModeEnabled: .constant(false),
            reasoningEffort: .constant(.xhigh),
            onDone: {}
        )

        XCTAssertEqual(padMetrics.sheetMaxWidth, 620)
        XCTAssertEqual(padMetrics.reasoningColumnWidth, 280)
        XCTAssertNil(phoneMetrics.sheetMaxWidth)
        XCTAssertNil(phoneMetrics.reasoningColumnWidth)
        XCTAssertEqual(sheet.effortShortLabel(.none), "Off")
        XCTAssertEqual(sheet.effortShortLabel(.medium), "Med")
        XCTAssertEqual(sheet.effortShortLabel(.xhigh), "Max")
    }

    func testStreamingTextSanitiserReplacesLatexDelimitersWithoutTouchingPlainText() {
        let text = """
        Intro $$x^2$$ and \\(y\\) then \\[z\\]
        ```swift
        print(1)
        ```
        """

        let sanitised = StreamingTextView.sanitiseText(text)

        XCTAssertTrue(sanitised.contains("[math]"))
        XCTAssertFalse(sanitised.contains("\\("))
        XCTAssertFalse(sanitised.contains("\\["))
        XCTAssertTrue(sanitised.contains("```swift"))
        XCTAssertTrue(sanitised.contains("print(1)"))
    }

    func testAppThemeColorSchemeMappingMatchesStoredTheme() {
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertEqual(AppTheme.light.colorScheme, .light)
        XCTAssertEqual(AppTheme.dark.colorScheme, .dark)
    }

    func testFilePreviewSheetComputesStableViewerMetrics() throws {
        let sheet = FilePreviewSheet(
            previewItem: FilePreviewItem(
                url: try makeSnapshotImageFile(),
                kind: .generatedImage,
                displayName: "Generated Chart",
                viewerFilename: "chart.png"
            )
        )

        XCTAssertEqual(sheet.fileURL.lastPathComponent, "snapshot-preview-image.png")
        XCTAssertFalse(sheet.isPad)
        XCTAssertGreaterThan(sheet.circularButtonDiameter, 0)
        XCTAssertGreaterThan(sheet.closeIconSize, 0)
        XCTAssertGreaterThan(sheet.actionIconSize, 0)
    }

    func testLoadGeneratedImagePreviewReturnsUnavailableForMissingFile() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-generated-image.png")
        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: missingURL) {
        case .unavailable:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected unavailable image preview")
        }
    }

    func testLoadGeneratedImagePreviewRejectsNonImageFilename() throws {
        let url = try makeSnapshotPDFFile()
        let renamed = url.deletingPathExtension().appendingPathExtension("txt")
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.copyItem(at: url, to: renamed)

        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: renamed) {
        case .error(let message):
            XCTAssertEqual(message, "This file is no longer recognized as an image.")
        default:
            XCTFail("Expected image filename validation failure")
        }
    }

    func testLoadGeneratedImagePreviewLoadsValidImage() throws {
        let url = try makeSnapshotImageFile()

        switch FilePreviewLoadingModel.loadGeneratedImagePreview(from: url) {
        case .image(let payload):
            XCTAssertFalse(payload.data.isEmpty)
        default:
            XCTFail("Expected valid generated image preview")
        }
    }

    func testLoadGeneratedPDFPreviewReturnsUnavailableForMissingFile() {
        let missingURL = URL(fileURLWithPath: "/tmp/missing-generated-document.pdf")
        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: missingURL) {
        case .unavailable:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected unavailable PDF preview")
        }
    }

    func testLoadGeneratedPDFPreviewRejectsNonPDFFilename() throws {
        let url = try makeSnapshotImageFile()
        let renamed = url.deletingPathExtension().appendingPathExtension("png")

        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: renamed) {
        case .error(let message):
            XCTAssertEqual(message, "This file is no longer recognized as a PDF.")
        default:
            XCTFail("Expected PDF filename validation failure")
        }
    }

    func testLoadGeneratedPDFPreviewLoadsValidPDF() throws {
        let url = try makeSnapshotPDFFile()

        switch FilePreviewLoadingModel.loadGeneratedPDFPreview(from: url) {
        case .document(let document):
            XCTAssertGreaterThan(document.pageCount, 0)
        default:
            XCTFail("Expected valid generated PDF preview")
        }
    }
}
