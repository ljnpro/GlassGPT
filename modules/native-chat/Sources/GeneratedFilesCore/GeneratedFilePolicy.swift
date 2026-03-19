import ChatDomain
import Foundation

/// Identifies the cache storage bucket for a generated file.
public enum GeneratedFileCacheBucket: String, CaseIterable, Sendable {
    /// Bucket for generated image files (PNG, JPEG, etc.).
    case image
    /// Bucket for generated document files (PDF, XLSX, etc.).
    case document

    /// The filesystem directory name used for this bucket under the caches root.
    public var directoryName: String {
        switch self {
        case .image:
            "generated-images"
        case .document:
            "generated-documents"
        }
    }
}

/// Determines how a generated file is presented to the user when opened.
public enum GeneratedFileOpenBehavior: String, CaseIterable, Sendable {
    /// Show the file in the in-app image preview viewer.
    case imagePreview
    /// Show the file in the in-app PDF preview viewer.
    case pdfPreview
    /// Present the file via the system share sheet for direct export.
    case directShare
}

/// Composite key used to look up a cached generated file.
public struct GeneratedFileCacheKey: Equatable, Hashable, Sendable {
    /// The download key (typically `fileId` or `containerId:fileId`).
    public let identity: String
    /// The cache bucket this file belongs to.
    public let bucket: GeneratedFileCacheBucket

    /// Creates a cache key.
    public init(identity: String, bucket: GeneratedFileCacheBucket) {
        self.identity = identity
        self.bucket = bucket
    }
}

/// Filename hints extracted from an HTTP download response.
public struct GeneratedFileResponseMetadata: Equatable, Sendable {
    /// Filename suggested by the URL response object.
    public let suggestedFilename: String?
    /// Filename extracted from the `Content-Disposition` header.
    public let contentDispositionFilename: String?

    /// Creates response metadata with optional filename hints.
    public init(
        suggestedFilename: String? = nil,
        contentDispositionFilename: String? = nil
    ) {
        self.suggestedFilename = suggestedFilename
        self.contentDispositionFilename = contentDispositionFilename
    }
}

/// Pure-function policy that resolves cache buckets, open behaviors, cache keys, and filenames
/// for generated files based on their descriptors and response metadata.
public enum GeneratedFilePolicy {
    /// Returns the appropriate cache bucket for the given file descriptor.
    public static func cacheBucket(for descriptor: GeneratedFileDescriptor) -> GeneratedFileCacheBucket {
        descriptor.isImage ? .image : .document
    }

    /// Returns the appropriate open behavior (image preview, PDF preview, or share) for the descriptor.
    public static func openBehavior(for descriptor: GeneratedFileDescriptor) -> GeneratedFileOpenBehavior {
        if descriptor.isImage {
            return .imagePreview
        }

        if descriptor.isPDF {
            return .pdfPreview
        }

        return .directShare
    }

    /// Builds a ``GeneratedFileCacheKey`` from the descriptor's download key and cache bucket.
    public static func cacheKey(for descriptor: GeneratedFileDescriptor) -> GeneratedFileCacheKey {
        GeneratedFileCacheKey(
            identity: descriptor.downloadKey,
            bucket: cacheBucket(for: descriptor)
        )
    }

    /// Resolves the best filename from the descriptor, response metadata, and an optional inferred extension.
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

    /// Sanitizes a candidate filename, optionally appending an inferred extension if none is present.
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
