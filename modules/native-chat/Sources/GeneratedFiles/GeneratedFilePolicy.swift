import ChatDomain
import Foundation

public enum GeneratedFileCacheBucket: String, CaseIterable, Sendable {
    case image
    case document

    public var directoryName: String {
        switch self {
        case .image:
            return "generated-images"
        case .document:
            return "generated-documents"
        }
    }
}

public enum GeneratedFileOpenBehavior: String, CaseIterable, Sendable {
    case imagePreview
    case pdfPreview
    case directShare
}

public struct GeneratedFileCacheKey: Equatable, Hashable, Sendable {
    public let identity: String
    public let bucket: GeneratedFileCacheBucket

    public init(identity: String, bucket: GeneratedFileCacheBucket) {
        self.identity = identity
        self.bucket = bucket
    }
}

public struct GeneratedFileResponseMetadata: Equatable, Sendable {
    public let suggestedFilename: String?
    public let contentDispositionFilename: String?

    public init(
        suggestedFilename: String? = nil,
        contentDispositionFilename: String? = nil
    ) {
        self.suggestedFilename = suggestedFilename
        self.contentDispositionFilename = contentDispositionFilename
    }
}

public enum GeneratedFilePolicy {
    public static func cacheBucket(for descriptor: GeneratedFileDescriptor) -> GeneratedFileCacheBucket {
        descriptor.isImage ? .image : .document
    }

    public static func openBehavior(for descriptor: GeneratedFileDescriptor) -> GeneratedFileOpenBehavior {
        if descriptor.isImage {
            return .imagePreview
        }

        if descriptor.isPDF {
            return .pdfPreview
        }

        return .directShare
    }

    public static func cacheKey(for descriptor: GeneratedFileDescriptor) -> GeneratedFileCacheKey {
        GeneratedFileCacheKey(
            identity: descriptor.downloadKey,
            bucket: cacheBucket(for: descriptor)
        )
    }

    public static func resolvedFilename(
        for descriptor: GeneratedFileDescriptor,
        responseMetadata: GeneratedFileResponseMetadata = .init(),
        inferredExtension: String? = nil
    ) -> String {
        let inferredExtension = normalizedExtension(inferredExtension)
        let candidates = [
            descriptor.filename,
            responseMetadata.contentDispositionFilename,
            responseMetadata.suggestedFilename
        ]

        for candidate in candidates {
            if let resolved = normalizedFilename(candidate, inferredExtension: inferredExtension) {
                return resolved
            }
        }

        return "\(descriptor.fileID).\(inferredExtension ?? "bin")"
    }

    public static func normalizedFilename(
        _ candidate: String?,
        inferredExtension: String? = nil
    ) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let sanitized = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !sanitized.isEmpty else {
            return nil
        }

        let ext = URL(fileURLWithPath: sanitized).pathExtension
        if !ext.isEmpty {
            return sanitized
        }

        guard let inferredExtension = normalizedExtension(inferredExtension) else {
            return sanitized
        }

        return "\(sanitized).\(inferredExtension)"
    }

    private static func normalizedExtension(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return trimmed.isEmpty ? nil : trimmed
    }
}
