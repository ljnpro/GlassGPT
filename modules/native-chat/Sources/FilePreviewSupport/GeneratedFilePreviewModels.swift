import Foundation
import PDFKit
import UIKit

/// The decoded image and its raw data for a generated image preview.
package struct GeneratedImagePreviewPayload: Equatable {
    package let image: UIImage
    package let data: Data

    package static func == (lhs: GeneratedImagePreviewPayload, rhs: GeneratedImagePreviewPayload) -> Bool {
        lhs.data == rhs.data
    }
}

/// The observable state of an image preview load lifecycle.
package enum GeneratedImagePreviewState {
    case loading
    case image(GeneratedImagePreviewPayload)
    case error(String)
}

/// The outcome of loading a generated image preview from disk.
package enum GeneratedImagePreviewLoadResult: Equatable {
    case image(GeneratedImagePreviewPayload)
    case error(String)
    case unavailable
}

/// The observable state of a PDF preview load lifecycle.
package enum GeneratedPDFPreviewState {
    case loading
    case document(PDFDocument)
    case error(String)
}

/// The outcome of loading a generated PDF preview from disk.
package enum GeneratedPDFPreviewLoadResult: Equatable {
    case document(PDFDocument)
    case error(String)
    case unavailable

    package static func == (lhs: GeneratedPDFPreviewLoadResult, rhs: GeneratedPDFPreviewLoadResult) -> Bool {
        switch (lhs, rhs) {
        case (.unavailable, .unavailable):
            true
        case let (.error(left), .error(right)):
            left == right
        case let (.document(left), .document(right)):
            left === right
        default:
            false
        }
    }
}

/// Tracks whether a generated file is currently being saved to the photo library or files.
package enum GeneratedFilePreviewSaveState: Equatable {
    case idle
    case saving
}
