import PDFKit
import Photos
import SwiftUI
import UIKit

/// Utility for saving image data to the user's photo library.
public enum PhotoLibraryImageSaver {
    /// Saves raw image data to the Photos library using the given original filename.
    public static func saveImageData(
        _ data: Data,
        originalFilename: String
    ) async throws(PhotoLibrarySaveError) {
        let result: Result<Void, PhotoLibrarySaveError> = await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                request.addResource(with: .photo, data: data, options: options)
            }) { success, error in
                if let error {
                    continuation.resume(
                        returning: .failure(
                            .photoLibraryFailure(error.localizedDescription)
                        )
                    )
                    return
                }

                if success {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(.unknown))
                }
            }
        }

        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }
}

/// SwiftUI wrapper around `UIActivityViewController` for sharing content.
public struct ActivityViewController: UIViewControllerRepresentable {
    /// The items to present in the share sheet.
    public let activityItems: [Any]

    /// Creates an activity view controller with the given items.
    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    /// Creates the system share sheet.
    public func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    /// No-op; the activity view controller does not support incremental updates.
    public func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}

/// SwiftUI wrapper that displays a `PDFDocument` using `PDFView` from PDFKit.
public struct GeneratedPDFView: UIViewRepresentable {
    /// The PDF document to render.
    public let document: PDFDocument
    /// Whether the surrounding interface is in dark mode, used to set the background color.
    public let isDarkAppearance: Bool

    /// Creates a PDF view for the given document and appearance.
    public init(document: PDFDocument, isDarkAppearance: Bool) {
        self.document = document
        self.isDarkAppearance = isDarkAppearance
    }

    /// Creates and configures a continuous-scroll PDF view.
    public func makeUIView(context _: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.autoScales = true
        pdfView.usePageViewController(false)
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = UIColor(isDarkAppearance ? .black : .white)
        pdfView.document = document
        return pdfView
    }

    /// Updates the document and background color when state changes.
    public func updateUIView(_ pdfView: PDFView, context _: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.backgroundColor = UIColor(isDarkAppearance ? .black : .white)
    }
}

/// Errors that can occur when saving an image to the photo library.
public enum PhotoLibrarySaveError: LocalizedError {
    /// The save operation failed for an unknown reason.
    case unknown
    /// The save operation failed with a system-provided message.
    case photoLibraryFailure(String)

    /// A user-facing description of the error.
    public var errorDescription: String? {
        switch self {
        case .unknown:
            "Unable to save this image to Photos."
        case let .photoLibraryFailure(message):
            message
        }
    }
}
