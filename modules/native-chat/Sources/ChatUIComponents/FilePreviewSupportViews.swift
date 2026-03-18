import PDFKit
import Photos
import SwiftUI
import UIKit

public enum PhotoLibraryImageSaver {
    public static func saveImageData(_ data: Data, originalFilename: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                request.addResource(with: .photo, data: data, options: options)
            }) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.unknown)
                }
            }
        }
    }
}

public struct ActivityViewController: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

public struct GeneratedPDFView: UIViewRepresentable {
    public let document: PDFDocument
    public let isDarkAppearance: Bool

    public init(document: PDFDocument, isDarkAppearance: Bool) {
        self.document = document
        self.isDarkAppearance = isDarkAppearance
    }

    public func makeUIView(context: Context) -> PDFView {
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

    public func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.backgroundColor = UIColor(isDarkAppearance ? .black : .white)
    }
}

public enum PhotoLibrarySaveError: LocalizedError {
    case unknown

    public var errorDescription: String? {
        switch self {
        case .unknown:
            return "Unable to save this image to Photos."
        }
    }
}
