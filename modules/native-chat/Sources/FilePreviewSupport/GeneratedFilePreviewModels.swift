import Foundation
import PDFKit
import UIKit

package struct GeneratedImagePreviewPayload: Equatable {
    package let image: UIImage
    package let data: Data

    package static func == (lhs: GeneratedImagePreviewPayload, rhs: GeneratedImagePreviewPayload) -> Bool {
        lhs.data == rhs.data
    }
}

package enum GeneratedImagePreviewState {
    case loading
    case image(GeneratedImagePreviewPayload)
    case error(String)
}

package enum GeneratedImagePreviewLoadResult: Equatable {
    case image(GeneratedImagePreviewPayload)
    case error(String)
    case unavailable
}

package enum GeneratedPDFPreviewState {
    case loading
    case document(PDFDocument)
    case error(String)
}

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

package enum GeneratedFilePreviewSaveState: Equatable {
    case idle
    case saving
}
