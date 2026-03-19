import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper around `UIDocumentPickerViewController` for selecting supported document types.
public struct DocumentPicker: UIViewControllerRepresentable {
    /// Callback invoked with the URLs of the documents the user selected.
    public let onDocumentsPicked: ([URL]) -> Void

    /// The set of uniform type identifiers accepted by the picker (PDF, Office formats, CSV).
    public static let supportedTypes: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("com.microsoft.word.doc") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        UTType("com.microsoft.powerpoint.ppt") ?? .data,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("com.microsoft.excel.xls") ?? .data,
        .commaSeparatedText
    ]

    /// Creates a document picker that reports selected URLs through the given closure.
    public init(onDocumentsPicked: @escaping ([URL]) -> Void) {
        self.onDocumentsPicked = onDocumentsPicked
    }

    /// Creates the system document picker configured for the supported types.
    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    /// No-op; the picker does not require incremental updates.
    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    /// Creates the coordinator that acts as the document picker delegate.
    public func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    /// Delegate coordinator that forwards document picker results to the parent callback.
    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentsPicked: ([URL]) -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }

        /// Forwards selected document URLs to the parent closure.
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        /// No-op handler for user cancellation.
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

/// Lightweight value holding a file's name, size, type extension, and raw data.
public struct FileMetadata {
    /// The display name of the file including its extension.
    public let filename: String
    /// Size of the file in bytes.
    public let fileSize: Int64
    /// Lowercased file extension string (e.g. "pdf", "docx").
    public let fileType: String
    /// The raw file contents.
    public let data: Data

    /// Reads the file at the given URL and returns a populated ``FileMetadata`` instance.
    public static func from(url: URL) throws -> FileMetadata {
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
