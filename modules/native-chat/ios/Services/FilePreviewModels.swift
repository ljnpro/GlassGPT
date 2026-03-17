import Foundation

enum FilePreviewKind: String, Sendable {
    case generatedImage
    case generatedPDF
}

struct FilePreviewItem: Identifiable, Sendable {
    let url: URL
    let kind: FilePreviewKind
    let displayName: String
    let viewerFilename: String

    var id: String { "\(kind.rawValue):\(url.path)" }
}

struct SharedGeneratedFileItem: Identifiable, Sendable {
    let url: URL
    let filename: String

    var id: String { url.path }
}
