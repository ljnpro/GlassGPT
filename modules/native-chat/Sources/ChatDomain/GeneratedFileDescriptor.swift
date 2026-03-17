import Foundation

public struct GeneratedFileDescriptor: Equatable, Hashable, Sendable {
    public let fileID: String
    public let containerID: String?
    public let filename: String?
    public let mediaType: String?

    public init(
        fileID: String,
        containerID: String? = nil,
        filename: String? = nil,
        mediaType: String? = nil
    ) {
        self.fileID = fileID
        self.containerID = Self.normalizedIdentifier(containerID)
        self.filename = Self.normalizedFilename(filename)
        self.mediaType = Self.normalizedMediaType(mediaType)
    }

    public var downloadKey: String {
        guard let containerID else {
            return fileID
        }

        return "\(containerID):\(fileID)"
    }

    public var pathExtension: String? {
        guard let filename else {
            return nil
        }

        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    public var isPDF: Bool {
        pathExtension == "pdf" || mediaType == "application/pdf"
    }

    public var isImage: Bool {
        guard let pathExtension else {
            return mediaType?.hasPrefix("image/") == true
        }

        return Self.imageExtensions.contains(pathExtension)
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    private static func normalizedIdentifier(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedFilename(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let component = URL(fileURLWithPath: trimmed).lastPathComponent
        return component.isEmpty ? nil : component
    }

    private static func normalizedMediaType(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
