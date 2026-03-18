import Foundation
import GeneratedFilesCore
import ImageIO
import PDFKit

extension FileDownloadService {
    func downloadKey(fileId: String, containerId: String?) -> String {
        if let containerId, !containerId.isEmpty {
            return "\(containerId):\(fileId)"
        }
        return fileId
    }

    func resolveFilename(
        suggestedFilename: String?,
        fileId: String,
        response: URLResponse,
        data: Data
    ) -> String {
        let inferredExtension = inferredFileExtension(from: response, data: data)

        if let suggested = normalizedFilename(suggestedFilename, inferredExtension: inferredExtension) {
            return suggested
        }

        if let httpResponse = response as? HTTPURLResponse,
           let disposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition"),
           let filenameRange = disposition.range(of: "filename=\""),
           let endRange = disposition[filenameRange.upperBound...].range(of: "\"") {
            let extracted = String(disposition[filenameRange.upperBound..<endRange.lowerBound])
            if let normalized = normalizedFilename(extracted, inferredExtension: inferredExtension) {
                return normalized
            }
        }

        if let responseSuggested = response.suggestedFilename,
           !responseSuggested.isEmpty,
           responseSuggested != "Unknown",
           let suggested = normalizedFilename(responseSuggested, inferredExtension: inferredExtension) {
            return suggested
        }

        return "\(fileId).\(inferredExtension ?? "bin")"
    }

    func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
        guard let candidate else { return nil }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !sanitized.isEmpty else { return nil }

        if !URL(fileURLWithPath: sanitized).pathExtension.isEmpty {
            return sanitized
        }

        if let inferredExtension, !inferredExtension.isEmpty {
            return "\(sanitized).\(inferredExtension)"
        }

        return sanitized
    }

    func inferredFileExtension(from response: URLResponse, data: Data) -> String? {
        if let mimeType = response.mimeType,
           let ext = Self.extensionForMimeType(mimeType) {
            return ext
        }

        return Self.extensionForFileSignature(data)
    }

    public static func openBehavior(for filename: String?) -> GeneratedFileOpenBehavior {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .imagePreview
        case "pdf":
            return .pdfPreview
        default:
            return .directShare
        }
    }

    public static func cacheBucket(for filename: String?) -> GeneratedFileCacheBucket {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .image
        default:
            return .document
        }
    }

    public static func isGeneratedImageFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }

        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return true
        default:
            return false
        }
    }

    public static func isGeneratedPDFFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf"
    }

    public static func isRenderableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
    }

    public static func isRenderablePDFData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return PDFDocument(data: data) != nil
    }
}
