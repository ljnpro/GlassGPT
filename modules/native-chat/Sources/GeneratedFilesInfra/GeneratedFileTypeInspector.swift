import Foundation

enum GeneratedFileTypeInspector {
    static func extensionForMimeType(_ mimeType: String) -> String? {
        let lower = mimeType.lowercased()
        switch lower {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/svg+xml": return "svg"
        case "image/webp": return "webp"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "image/x-icon": return "ico"
        case "application/pdf": return "pdf"
        case "text/plain": return "txt"
        case "text/csv": return "csv"
        case "text/tab-separated-values": return "tsv"
        case "text/html": return "html"
        case "text/markdown": return "md"
        case "application/json": return "json"
        case "application/geo+json": return "geojson"
        case "application/xml", "text/xml": return "xml"
        case "application/yaml", "text/yaml": return "yaml"
        case "application/x-yaml": return "yml"
        case "application/toml": return "toml"
        case "application/zip": return "zip"
        case "application/gzip": return "gz"
        case "application/x-bzip2": return "bz2"
        case "application/x-xz": return "xz"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": return "xlsx"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document": return "docx"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation": return "pptx"
        case "application/vnd.oasis.opendocument.spreadsheet": return "ods"
        case "application/vnd.oasis.opendocument.text": return "odt"
        case "application/vnd.oasis.opendocument.presentation": return "odp"
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/mpeg": return "mp3"
        case "audio/ogg": return "ogg"
        case "audio/flac": return "flac"
        default:
            if lower.hasPrefix("text/") { return "txt" }
            if lower.hasPrefix("image/") { return lower.replacingOccurrences(of: "image/", with: "") }
            return nil
        }
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
