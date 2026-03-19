import Foundation

/// A generated file that has been downloaded and cached locally.
public struct GeneratedFileLocalResource: Sendable, Equatable {
    /// Local filesystem URL where the file is stored.
    public let localURL: URL
    /// The resolved filename for display and sharing.
    public let filename: String
    /// The cache bucket this file is stored in.
    public let cacheBucket: GeneratedFileCacheBucket
    /// How the file should be presented when the user taps it.
    public let openBehavior: GeneratedFileOpenBehavior

    /// Creates a local resource descriptor.
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

/// The kind of in-app preview to display for a generated file.
public enum FilePreviewKind: String, Sendable, Equatable {
    /// A raster image preview (PNG, JPEG).
    case generatedImage
    /// A PDF document preview.
    case generatedPDF
}

/// Model for presenting a generated file in the in-app preview viewer.
public struct FilePreviewItem: Identifiable, Sendable, Equatable {
    /// Local file URL to display.
    public let url: URL
    /// The kind of preview (image or PDF).
    public let kind: FilePreviewKind
    /// Human-readable name shown in the viewer title.
    public let displayName: String
    /// Filename used for the viewer's share/export action.
    public let viewerFilename: String

    /// Creates a preview item.
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

    /// Stable identifier combining the preview kind and file path.
    public var id: String {
        "\(kind.rawValue):\(url.path)"
    }
}

/// Model for sharing a generated file via the system share sheet.
public struct SharedGeneratedFileItem: Identifiable, Sendable, Equatable {
    /// Local file URL to share.
    public let url: URL
    /// The filename presented in the share sheet.
    public let filename: String

    /// Creates a shared file item.
    public init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
    }

    /// Stable identifier derived from the file path.
    public var id: String {
        url.path
    }
}
