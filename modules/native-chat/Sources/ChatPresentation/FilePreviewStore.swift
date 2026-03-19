import Foundation
import GeneratedFilesCore
import Observation

/// Observable store that tracks the current file preview/share state for the chat UI.
///
/// All properties are `@MainActor`-isolated.
@Observable
@MainActor
public final class FilePreviewStore {
    /// The item currently being previewed in the in-app viewer, or `nil`.
    public var filePreviewItem: FilePreviewItem?
    /// The item currently being shared via the system share sheet, or `nil`.
    public var sharedGeneratedFileItem: SharedGeneratedFileItem?
    /// Whether a file download is currently in progress.
    public var isDownloadingFile = false
    /// A user-facing error message if the last download failed.
    public var fileDownloadError: String?

    /// Creates a new, empty file preview store.
    public init() {}

    /// Resets all preview state to its initial values.
    public func clear() {
        filePreviewItem = nil
        sharedGeneratedFileItem = nil
        isDownloadingFile = false
        fileDownloadError = nil
    }
}
