import QuickLook
import SwiftUI

/// SwiftUI wrapper around `QLPreviewController` for previewing a single file.
public struct FilePreviewController: UIViewControllerRepresentable {
    /// URL of the file to preview.
    public let fileURL: URL

    /// Creates a file preview controller for the given local file URL.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Creates the coordinator that serves as the Quick Look data source.
    public func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    /// Creates a navigation controller wrapping a Quick Look preview controller.
    public func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    /// Reloads preview data when the file URL changes.
    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.fileURL = fileURL
        if let qlController = uiViewController.viewControllers.first as? QLPreviewController {
            qlController.reloadData()
        }
    }

    /// Data source coordinator that provides the single file URL to Quick Look.
    public final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
            super.init()
        }

        /// Returns 1 since this controller previews a single file.
        public func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            1
        }

        /// Returns the file URL as the preview item.
        public func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
            fileURL as NSURL
        }
    }
}
