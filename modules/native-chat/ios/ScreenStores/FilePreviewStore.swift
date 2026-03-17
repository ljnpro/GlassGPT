import Foundation

@Observable
@MainActor
final class FilePreviewStore {
    var filePreviewItem: FilePreviewItem?
    var sharedGeneratedFileItem: SharedGeneratedFileItem?
    var isDownloadingFile = false
    var fileDownloadError: String?

    func clear() {
        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        isDownloadingFile = false
        fileDownloadError = nil
    }
}
