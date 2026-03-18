import SwiftUI
import UniformTypeIdentifiers

public struct DocumentPicker: UIViewControllerRepresentable {
    public let onDocumentsPicked: ([URL]) -> Void

    public static let supportedTypes: [UTType] = [
        .pdf,
        UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
        UTType("com.microsoft.word.doc") ?? .data,
        UTType("org.openxmlformats.presentationml.presentation") ?? .data,
        UTType("com.microsoft.powerpoint.ppt") ?? .data,
        UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data,
        UTType("com.microsoft.excel.xls") ?? .data,
        .commaSeparatedText,
    ]

    public init(onDocumentsPicked: @escaping ([URL]) -> Void) {
        self.onDocumentsPicked = onDocumentsPicked
    }

    public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.supportedTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    public final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onDocumentsPicked: ([URL]) -> Void

        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }

        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onDocumentsPicked(urls)
        }

        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}

public struct FileMetadata {
    public let filename: String
    public let fileSize: Int64
    public let fileType: String
    public let data: Data

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
