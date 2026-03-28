import Foundation
import ImageIO
import PDFKit
import UIKit

package enum GeneratedFilePreviewLoader {
    package static func loadGeneratedImagePreview(
        from fileURL: URL,
        onFailure: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> GeneratedImagePreviewLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            reportLoadFailure(
                kind: "image",
                fileURL: fileURL,
                error: error,
                onFailure: onFailure,
                logFailure: logFailure
            )
            return .unavailable
        }

        guard !data.isEmpty else {
            return .unavailable
        }

        guard isGeneratedImageFilename(fileURL.lastPathComponent) else {
            return .error("This file is no longer recognized as an image.")
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return .error("This generated image could not be rendered.")
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(
            imageSource,
            0,
            [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
        ) else {
            return .error("This generated image could not be rendered.")
        }

        return .image(
            GeneratedImagePreviewPayload(
                image: UIImage(cgImage: cgImage),
                data: data
            )
        )
    }

    package static func loadGeneratedPDFPreview(
        from fileURL: URL,
        onFailure: ((String) -> Void)? = nil,
        logFailure: Bool = true
    ) -> GeneratedPDFPreviewLoadResult {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            reportLoadFailure(
                kind: "PDF",
                fileURL: fileURL,
                error: error,
                onFailure: onFailure,
                logFailure: logFailure
            )
            return .unavailable
        }

        guard !data.isEmpty else {
            return .unavailable
        }

        guard isGeneratedPDFFilename(fileURL.lastPathComponent) else {
            return .error("This file is no longer recognized as a PDF.")
        }

        guard let document = PDFDocument(data: data) else {
            return .error("This generated PDF could not be rendered.")
        }

        return .document(document)
    }

    private static func isGeneratedImageFilename(_ filename: String) -> Bool {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "bmp", "tiff", "heic"].contains(ext)
    }

    private static func isGeneratedPDFFilename(_ filename: String) -> Bool {
        URL(fileURLWithPath: filename).pathExtension.lowercased() == "pdf"
    }

    private static func reportLoadFailure(
        kind: String,
        fileURL: URL,
        error: some Error,
        onFailure: ((String) -> Void)?,
        logFailure: Bool
    ) {
        let message = "Failed to load generated \(kind) preview at \(fileURL.path): \(error.localizedDescription)"
        onFailure?(message)
        if logFailure {
            NSLog("%@", message)
        }
    }
}
