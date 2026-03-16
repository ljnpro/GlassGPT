import XCTest
@testable import NativeChat

final class GeneratedFileCoordinatorTests: XCTestCase {
    func testRequestedFilenamePrefersAnnotationThenSandboxPath() {
        let coordinator = GeneratedFileCoordinator()
        let annotation = FilePathAnnotation(
            fileId: "file_chart",
            containerId: "container_123",
            sandboxPath: "/mnt/data/chart.png",
            filename: "chart.png",
            startIndex: 0,
            endIndex: 5
        )

        XCTAssertEqual(
            coordinator.requestedFilename(
                for: "sandbox:/mnt/data/fallback.png",
                annotation: annotation
            ),
            "chart.png"
        )
        XCTAssertEqual(
            coordinator.requestedFilename(
                for: "sandbox:/mnt/data/fallback.png",
                annotation: nil
            ),
            "fallback.png"
        )
    }

    func testFindMatchingFilePathAnnotationPrefersFallbackFileIDAndExactPath() {
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

        XCTAssertEqual(
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
            )?.fileId,
            "file_secondary"
        )

        XCTAssertEqual(
            coordinator.findMatchingFilePathAnnotation(
                in: [primary, fallback],
                sandboxURL: "sandbox:/mnt/data/primary.png",
                fallback: nil
            )?.fileId,
            "file_primary"
        )
    }

    func testPresentationBuildsImagePreviewWithoutChangingNames() {
        let coordinator = GeneratedFileCoordinator()
        let resource = GeneratedFileLocalResource(
            localURL: URL(fileURLWithPath: "/tmp/chart.png"),
            filename: "chart.png",
            cacheBucket: .image,
            openBehavior: .imagePreview
        )

        switch coordinator.presentation(for: resource, suggestedFilename: "ignored.png") {
        case .preview(let item):
            XCTAssertEqual(item.kind.rawValue, FilePreviewKind.generatedImage.rawValue)
            XCTAssertEqual(item.displayName, "chart")
            XCTAssertEqual(item.viewerFilename, "chart.png")
        default:
            XCTFail("Expected image resource to open in preview")
        }
    }

    func testUserFacingDownloadErrorPreservesExistingMessages() {
        let coordinator = GeneratedFileCoordinator()

        XCTAssertEqual(
            coordinator.userFacingDownloadError(
                FileDownloadError.invalidPDFData,
                openBehavior: .pdfPreview
            ),
            "This generated PDF could not be rendered."
        )
        XCTAssertEqual(
            coordinator.userFacingDownloadError(
                FileDownloadError.httpError(410, "expired"),
                openBehavior: .directShare
            ),
            "This generated file has expired and can no longer be downloaded. Please regenerate it."
        )
    }
}
