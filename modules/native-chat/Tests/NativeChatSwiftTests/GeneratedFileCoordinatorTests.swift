import Foundation
import Testing
import ChatDomain
import ChatPersistenceSwiftData
import GeneratedFilesCore
import GeneratedFilesInfra
@testable import NativeChatComposition

struct GeneratedFileCoordinatorTests {
    @Test func requestedFilenamePrefersAnnotationThenSandboxPath() {
        let coordinator = GeneratedFileCoordinator()
        let annotation = FilePathAnnotation(
            fileId: "file_chart",
            containerId: "container_123",
            sandboxPath: "/mnt/data/chart.png",
            filename: "chart.png",
            startIndex: 0,
            endIndex: 5
        )

        #expect(
            coordinator.requestedFilename(
                for: "sandbox:/mnt/data/fallback.png",
                annotation: annotation
            ) ==
            "chart.png"
        )
        #expect(
            coordinator.requestedFilename(
                for: "sandbox:/mnt/data/fallback.png",
                annotation: nil
            ) ==
            "fallback.png"
        )
    }

    @Test func findMatchingFilePathAnnotationPrefersFallbackFileIDAndExactPath() {
        let coordinator = GeneratedFileCoordinator()
        let primary = FilePathAnnotation(
            fileId: "file_primary",
            containerId: nil,
            sandboxPath: "/mnt/data/primary.png",
            filename: "primary.png",
            startIndex: 0,
            endIndex: 10
        )
        let fallback = FilePathAnnotation(
            fileId: "file_secondary",
            containerId: "container_123",
            sandboxPath: "/mnt/data/secondary.pdf",
            filename: "secondary.pdf",
            startIndex: 11,
            endIndex: 24
        )

        #expect(
            coordinator.findMatchingFilePathAnnotation(
                in: [primary, fallback],
                sandboxURL: "sandbox:/mnt/data/unknown",
                fallback: FilePathAnnotation(
                    fileId: "file_secondary",
                    containerId: nil,
                    sandboxPath: "",
                    filename: nil,
                    startIndex: 0,
                    endIndex: 0
                )
            )?.fileId ==
            "file_secondary"
        )

        #expect(
            coordinator.findMatchingFilePathAnnotation(
                in: [primary, fallback],
                sandboxURL: "sandbox:/mnt/data/primary.png",
                fallback: nil
            )?.fileId ==
            "file_primary"
        )
    }

    @Test func presentationBuildsImagePreviewWithoutChangingNames() {
        let coordinator = GeneratedFileCoordinator()
        let resource = GeneratedFileLocalResource(
            localURL: URL(fileURLWithPath: "/tmp/chart.png"),
            filename: "chart.png",
            cacheBucket: .image,
            openBehavior: .imagePreview
        )

        switch coordinator.presentation(for: resource, suggestedFilename: "ignored.png") {
        case .preview(let item):
            #expect(item.kind.rawValue == FilePreviewKind.generatedImage.rawValue)
            #expect(item.displayName == "chart")
            #expect(item.viewerFilename == "chart.png")
        default:
            Issue.record("Expected image resource to open in preview")
        }
    }

    @Test func userFacingDownloadErrorPreservesExistingMessages() {
        let coordinator = GeneratedFileCoordinator()

        #expect(
            coordinator.userFacingDownloadError(
                FileDownloadError.invalidPDFData,
                openBehavior: .pdfPreview
            ) ==
            "This generated PDF could not be rendered."
        )
        #expect(
            coordinator.userFacingDownloadError(
                FileDownloadError.httpError(410, "expired"),
                openBehavior: .directShare
            ) ==
            "This generated file has expired and can no longer be downloaded. Please regenerate it."
        )
    }
}
