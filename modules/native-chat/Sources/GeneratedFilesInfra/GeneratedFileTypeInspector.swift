import Foundation

enum GeneratedFileTypeInspector {
    private static let mimeTypeExtensions: [String: String] = [
        "image/png": "png",
        "image/jpeg": "jpg",
        "image/gif": "gif",
        "image/svg+xml": "svg",
        "image/webp": "webp",
        "image/bmp": "bmp",
        "image/tiff": "tiff",
        "image/x-icon": "ico",
        "application/pdf": "pdf",
        "text/plain": "txt",
        "text/csv": "csv",
        "text/tab-separated-values": "tsv",
        "text/html": "html",
        "text/markdown": "md",
        "application/json": "json",
        "application/geo+json": "geojson",
        "application/xml": "xml",
        "text/xml": "xml",
        "application/yaml": "yaml",
        "text/yaml": "yaml",
        "application/x-yaml": "yml",
        "application/toml": "toml",
        "application/zip": "zip",
        "application/gzip": "gz",
        "application/x-bzip2": "bz2",
        "application/x-xz": "xz",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
        "application/vnd.oasis.opendocument.spreadsheet": "ods",
        "application/vnd.oasis.opendocument.text": "odt",
        "application/vnd.oasis.opendocument.presentation": "odp",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/mpeg": "mp3",
        "audio/ogg": "ogg",
        "audio/flac": "flac"
    ]

    static func extensionForMimeType(_ mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        if let extensionName = mimeTypeExtensions[lower] {
            return extensionName
        }
        if lower.hasPrefix("text/") {
            return "txt"
        }
        if lower.hasPrefix("image/") {
            return String(lower.dropFirst("image/".count))
        }
        return nil
    }

    static func extensionForFileSignature(_ data: Data) -> String? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if data.starts(with: Array("GIF8".utf8)) {
            return "gif"
        }
        if data.starts(with: Array("%PDF".utf8)) {
            return "pdf"
        }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            return "zip"
        }
        if data.starts(with: [0x1F, 0x8B]) {
            return "gz"
        }
        if data.starts(with: Array("BZh".utf8)) {
            return "bz2"
        }
        if data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            return "xz"
        }
        if data.starts(with: Array("SQLite format 3\u{0}".utf8)) {
            return "sqlite"
        }

        if data.count >= 12 {
            let prefix = data.prefix(12)
            if prefix.prefix(4) == Data("RIFF".utf8), prefix.suffix(4) == Data("WEBP".utf8) {
                return "webp"
            }
            if prefix.prefix(4) == Data("RIFF".utf8), prefix.suffix(4) == Data("WAVE".utf8) {
                return "wav"
            }
        }

        if data.starts(with: Array("OggS".utf8)) {
            return "ogg"
        }
        if data.starts(with: Array("fLaC".utf8)) {
            return "flac"
        }

        return nil
    }
}
