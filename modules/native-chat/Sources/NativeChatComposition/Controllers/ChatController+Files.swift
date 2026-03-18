import ChatDomain
import GeneratedFilesCore
import GeneratedFilesInfra
import ChatPersistenceSwiftData
import Foundation

@MainActor
extension ChatController {
    func handleSandboxLinkTap(message: Message, sandboxURL: String, annotation: FilePathAnnotation?) {
        fileInteractionCoordinator.handleSandboxLinkTap(message: message, sandboxURL: sandboxURL, annotation: annotation)
    }

    func resolveDownloadAnnotation(
        for message: Message,
        sandboxURL: String,
        fallback: FilePathAnnotation?,
        apiKey: String
    ) async throws -> FilePathAnnotation? {
        try await fileInteractionCoordinator.resolveDownloadAnnotation(
            for: message,
            sandboxURL: sandboxURL,
            fallback: fallback,
            apiKey: apiKey
        )
    }

    func applyGeneratedFilePresentation(_ presentation: GeneratedFilePresentation) {
        fileInteractionCoordinator.applyGeneratedFilePresentation(presentation)
    }

    func prefetchGeneratedFilesIfNeeded(for message: Message) {
        fileInteractionCoordinator.prefetchGeneratedFilesIfNeeded(for: message)
    }
}
