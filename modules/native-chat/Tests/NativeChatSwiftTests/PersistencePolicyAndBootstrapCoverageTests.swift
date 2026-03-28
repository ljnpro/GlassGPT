import ChatDomain
import Foundation
import GeneratedFilesCore
import SwiftData
import Testing
@testable import ChatProjectionPersistence
@testable import GeneratedFilesCache

@Suite(.tags(.persistence))
struct PersistencePolicyAndBootstrapCoverageTests {
    @MainActor
    @Test func `generated file cache policy identifies previews and renderable data`() throws {
        #expect(GeneratedFileCachePolicy.openBehavior(for: "image.png") == .imagePreview)
        #expect(GeneratedFileCachePolicy.openBehavior(for: "report.pdf") == .pdfPreview)
        #expect(GeneratedFileCachePolicy.openBehavior(for: "archive.zip") == .directShare)
        #expect(GeneratedFileCachePolicy.cacheBucket(for: "photo.jpg") == .image)
        #expect(GeneratedFileCachePolicy.cacheBucket(for: "archive.zip") == .document)
        #expect(GeneratedFileCachePolicy.isGeneratedImageFilename("photo.jpeg"))
        #expect(!GeneratedFileCachePolicy.isGeneratedImageFilename(nil))
        #expect(GeneratedFileCachePolicy.isGeneratedPDFFilename("report.pdf"))
        #expect(!GeneratedFileCachePolicy.isGeneratedPDFFilename("report.png"))

        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0b8AAAAASUVORK5CYII="
        )
        let pdfData = try Data(contentsOf: makeSnapshotPDFFile())

        #expect(GeneratedFileCachePolicy.isRenderableImageData(pngData ?? Data()))
        #expect(!GeneratedFileCachePolicy.isRenderableImageData(Data()))
        #expect(GeneratedFileCachePolicy.isRenderablePDFData(pdfData))
        #expect(!GeneratedFileCachePolicy.isRenderablePDFData(Data()))
    }

    @Test func `generated file models expose stable identity`() {
        let url = URL(fileURLWithPath: "/tmp/demo.pdf")
        let localResource = GeneratedFileLocalResource(
            localURL: url,
            filename: "demo.pdf",
            cacheBucket: .document,
            openBehavior: .pdfPreview
        )
        let previewItem = FilePreviewItem(
            url: url,
            kind: .generatedPDF,
            displayName: "Demo",
            viewerFilename: "demo.pdf"
        )
        let sharedItem = SharedGeneratedFileItem(url: url, filename: "demo.pdf")

        #expect(localResource.filename == "demo.pdf")
        #expect(previewItem.id == "generatedPDF:/tmp/demo.pdf")
        #expect(sharedItem.id == "/tmp/demo.pdf")
    }

    @MainActor
    @Test func `native chat persistence reports recovery and hard failure states`() {
        var messages: [String] = []
        let recovered = NativeChatPersistence.createPersistentContainer(
            makePersistentContainer: {
                struct InitialFailure: LocalizedError {
                    var errorDescription: String? {
                        "initial failure"
                    }
                }
                if messages.isEmpty {
                    throw InitialFailure()
                }
                return try makePersistenceCoverageInMemoryModelContainer()
            },
            preserveExistingStore: {
                messages.append("preserved")
                return NativeChatPersistence.StoreRecoveryOutcome(
                    didRecoverPersistentStore: true,
                    failureMessage: "preserved failed store"
                )
            },
            makeFallbackContainer: {
                nil
            },
            logError: { messages.append($0) }
        )

        #expect(recovered.container != nil)
        #expect(recovered.didRecoverPersistentStore)
        #expect(recovered.startupErrorDescription == nil)
        #expect(messages.contains("[NativeChatPersistence] preserved failed store"))

        let failed = NativeChatPersistence.createPersistentContainer(
            makePersistentContainer: {
                throw NativeChatPersistenceHarnessError.bootstrapFailed
            },
            preserveExistingStore: {
                NativeChatPersistence.StoreRecoveryOutcome(
                    didRecoverPersistentStore: false,
                    failureMessage: nil
                )
            },
            makeFallbackContainer: {
                nil
            },
            logError: { _ in }
        )

        #expect(failed.container == nil)
        #expect(
            failed.startupErrorDescription
                == "Failed to initialize local chat storage. Restart the app and try again."
        )
    }
}

private enum NativeChatPersistenceHarnessError: LocalizedError {
    case bootstrapFailed

    var errorDescription: String? {
        "bootstrap failed"
    }
}

@MainActor
private func makePersistenceCoverageInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Conversation.self,
        Message.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
