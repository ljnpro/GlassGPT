import QuickLook
import SwiftUI

public struct FilePreviewController: UIViewControllerRepresentable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(fileURL: fileURL)
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.fileURL = fileURL
        if let qlController = uiViewController.viewControllers.first as? QLPreviewController {
            qlController.reloadData()
        }
    }

    public final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var fileURL: URL

        init(fileURL: URL) {
            self.fileURL = fileURL
            super.init()
        }

        public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            fileURL as NSURL
        }
    }
}
