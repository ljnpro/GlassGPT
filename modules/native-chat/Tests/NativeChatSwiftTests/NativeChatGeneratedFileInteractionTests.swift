import ChatDomain
import ChatPresentation
import Foundation
import GeneratedFilesCache
import GeneratedFilesCore
import Testing
@testable import NativeChatBackendCore

@Suite(.tags(.runtime, .presentation))
@MainActor
struct NativeChatGeneratedFileInteractionTests {
    @Test func `downloads image files and presents a preview item`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let previewStore = FilePreviewStore()
        let cacheManager = GeneratedFileCacheManager(cacheRootOverride: harness.cacheRoot)
        let coordinator = GeneratedFileInteractionCoordinator(
            client: harness.client,
            cacheManager: cacheManager,
            filePreviewStore: previewStore
        )
        let imageURL = try makeSnapshotImageFile()
        let imageData = try Data(contentsOf: imageURL)
        harness.client.downloadGeneratedFileResult = .success((imageData, "image/png"))

        await coordinator.handleSandboxLinkTap(
            "sandbox:/mnt/data/chart.png",
            annotation: FilePathAnnotation(
                fileId: "file_image",
                containerId: "container_1",
                sandboxPath: "/mnt/data/chart.png",
                filename: "chart.png",
                startIndex: 0,
                endIndex: 5
            )
        )

        #expect(harness.client.downloadGeneratedFileCalls == [
            .init(fileID: "file_image", containerID: "container_1")
        ])
        #expect(previewStore.filePreviewItem?.kind == .generatedImage)
        #expect(previewStore.filePreviewItem?.viewerFilename == "chart.png")
        #expect(previewStore.sharedGeneratedFileItem == nil)
        #expect(previewStore.fileDownloadError == nil)
    }

    @Test func `cached generated files skip re-downloads on repeated taps`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let previewStore = FilePreviewStore()
        let cacheManager = GeneratedFileCacheManager(cacheRootOverride: harness.cacheRoot)
        let coordinator = GeneratedFileInteractionCoordinator(
            client: harness.client,
            cacheManager: cacheManager,
            filePreviewStore: previewStore
        )
        let imageURL = try makeSnapshotImageFile()
        let imageData = try Data(contentsOf: imageURL)
        harness.client.downloadGeneratedFileResult = .success((imageData, "image/png"))
        let annotation = FilePathAnnotation(
            fileId: "file_cached",
            containerId: "container_1",
            sandboxPath: "/mnt/data/chart.png",
            filename: "chart.png",
            startIndex: 0,
            endIndex: 5
        )

        await coordinator.handleSandboxLinkTap("sandbox:/mnt/data/chart.png", annotation: annotation)
        await coordinator.handleSandboxLinkTap("sandbox:/mnt/data/chart.png", annotation: annotation)

        #expect(harness.client.downloadGeneratedFileCalls.count == 1)
        #expect(previewStore.filePreviewItem?.viewerFilename == "chart.png")
    }

    @Test func `non previewable downloads open the share sheet instead of preview`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let previewStore = FilePreviewStore()
        let cacheManager = GeneratedFileCacheManager(cacheRootOverride: harness.cacheRoot)
        let coordinator = GeneratedFileInteractionCoordinator(
            client: harness.client,
            cacheManager: cacheManager,
            filePreviewStore: previewStore
        )
        harness.client.downloadGeneratedFileResult = .success((Data("a,b\n1,2".utf8), "text/csv"))

        await coordinator.handleSandboxLinkTap(
            "sandbox:/mnt/data/report.csv",
            annotation: FilePathAnnotation(
                fileId: "file_csv",
                containerId: "container_1",
                sandboxPath: "/mnt/data/report.csv",
                filename: "report.csv",
                startIndex: 0,
                endIndex: 6
            )
        )

        #expect(previewStore.filePreviewItem == nil)
        #expect(previewStore.sharedGeneratedFileItem?.filename == "report.csv")
        #expect(previewStore.fileDownloadError == nil)
    }

    @Test func `missing annotations surface a download error`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let previewStore = FilePreviewStore()
        let cacheManager = GeneratedFileCacheManager(cacheRootOverride: harness.cacheRoot)
        let coordinator = GeneratedFileInteractionCoordinator(
            client: harness.client,
            cacheManager: cacheManager,
            filePreviewStore: previewStore
        )

        await coordinator.handleSandboxLinkTap("sandbox:/mnt/data/missing.txt", annotation: nil)

        #expect(harness.client.downloadGeneratedFileCalls.isEmpty)
        #expect(previewStore.fileDownloadError == "This generated file is no longer available.")
    }
}
