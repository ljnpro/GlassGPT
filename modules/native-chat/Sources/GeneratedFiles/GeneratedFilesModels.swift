import Foundation

package enum GeneratedFileStoreError: Error, LocalizedError, Sendable {
    case invalidCacheRoot

    package var errorDescription: String? {
        switch self {
        case .invalidCacheRoot:
            return "Unable to create the generated file cache."
        }
    }
}

public struct GeneratedFileLocalResource: Sendable {
    public let localURL: URL
    public let filename: String
    public let cacheBucket: GeneratedFileCacheBucket
    public let openBehavior: GeneratedFileOpenBehavior

    public init(
        localURL: URL,
        filename: String,
        cacheBucket: GeneratedFileCacheBucket,
        openBehavior: GeneratedFileOpenBehavior
    ) {
        self.localURL = localURL
        self.filename = filename
        self.cacheBucket = cacheBucket
        self.openBehavior = openBehavior
    }
}

public enum FilePreviewKind: String, Sendable {
    case generatedImage
    case generatedPDF
}

public struct FilePreviewItem: Identifiable, Sendable {
    public let url: URL
    public let kind: FilePreviewKind
    public let displayName: String
    public let viewerFilename: String

    public init(
        url: URL,
        kind: FilePreviewKind,
        displayName: String,
        viewerFilename: String
    ) {
        self.url = url
        self.kind = kind
        self.displayName = displayName
        self.viewerFilename = viewerFilename
    }

    public var id: String { "\(kind.rawValue):\(url.path)" }
}

public struct SharedGeneratedFileItem: Identifiable, Sendable {
    public let url: URL
    public let filename: String

    public init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
    }

    public var id: String { url.path }
}
