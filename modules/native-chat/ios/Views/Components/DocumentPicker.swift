import SwiftUI
import UniformTypeIdentifiers

/// A UIViewControllerRepresentable wrapper for UIDocumentPickerViewController.
/// Supports selecting PDF, DOCX, PPTX, CSV, XLSX files.
struct DocumentPicker: UIViewControllerRepresentable {
    let onDocumentsPicked: ([URL]) -> Void

    /// Supported document types
    static let supportedTypes: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,  // docx
        UTType("com.microsoft.word.doc") ?? .data,                         // doc
        UTType("org.openxmlformats.presentationml.presentation") ?? .data, // pptx
        UTType("com.microsoft.powerpoint.ppt") ?? .data,                   // ppt
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,         // xlsx
        UTType("com.microsoft.excel.xls") ?? .data,                        // xls
        .commaSeparatedText,                                                // csv
    ]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentsPicked: ([URL]) -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // No action needed
        }
    }
}

/// Helper to extract file metadata from a URL.
struct FileMetadata {
    let filename: String
    let fileSize: Int64
    let fileType: String
    let data: Data

    /// Create FileMetadata from a local file URL (must be a copy, not a security-scoped URL).
    static func from(url: URL) throws -> FileMetadata {
        let filename = url.lastPathComponent
        let fileType = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        let fileSize = Int64(data.count)

        return FileMetadata(
            filename: filename,
            fileSize: fileSize,
            fileType: fileType,
            data: data
        )
    }
}
