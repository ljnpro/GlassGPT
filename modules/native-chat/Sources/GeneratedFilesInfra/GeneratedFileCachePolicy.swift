import Foundation
import GeneratedFilesCore
import ImageIO
import PDFKit

enum GeneratedFileCachePolicy {
    static func openBehavior(for filename: String?) -> GeneratedFileOpenBehavior {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .imagePreview
        case "pdf":
            return .pdfPreview
        default:
            return .directShare
        }
    }

    static func cacheBucket(for filename: String?) -> GeneratedFileCacheBucket {
        switch URL(fileURLWithPath: filename ?? "").pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return .image
        default:
            return .document
        }
    }

    static func isGeneratedImageFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }

        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png", "jpg", "jpeg":
            return true
        default:
            return false
        }
    }

    static func isGeneratedPDFFilename(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf"
    }

    static func isRenderableImageData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }

        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil) != nil
    }

    static func isRenderablePDFData(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        return PDFDocument(data: data) != nil
    }
}
