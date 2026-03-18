import Foundation
import GeneratedFilesCore
import Observation

@Observable
@MainActor
public final class FilePreviewStore {
    public var filePreviewItem: FilePreviewItem?
    public var sharedGeneratedFileItem: SharedGeneratedFileItem?
    public var isDownloadingFile = false
    public var fileDownloadError: String?

    public init() {}

    public func clear() {
        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        isDownloadingFile = false
        fileDownloadError = nil
    }
}
