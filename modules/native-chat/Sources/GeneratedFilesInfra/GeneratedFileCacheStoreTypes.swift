import Foundation

/// Errors originating from cache store filesystem operations.
package enum GeneratedFileStoreError: Error, LocalizedError {
    /// The cache root directory could not be created.
    case invalidCacheRoot
    /// A filesystem operation failed with an underlying system error.
    case fileSystemError(underlying: any Error)

    /// A human-readable description of the error.
    package var errorDescription: String? {
        switch self {
        case .invalidCacheRoot:
            "Unable to create the generated file cache."
        case let .fileSystemError(underlying):
            "File system operation failed: \(underlying.localizedDescription)"
        }
    }
}

package extension GeneratedFileCacheStore {
    /// Represents a single cached file with its location and metadata.
    struct CachedEntry {
        /// The parent directory containing this cached file.
        let directoryURL: URL
        /// The URL of the cached file itself.
        let fileURL: URL
        /// Size of the cached file in bytes.
        let size: Int64
        /// Last modification date, used for LRU eviction.
        let modifiedAt: Date

        /// Creates a cached entry.
        init(
            directoryURL: URL,
            fileURL: URL,
            size: Int64,
            modifiedAt: Date
        ) {
            self.directoryURL = directoryURL
            self.fileURL = fileURL
            self.size = size
            self.modifiedAt = modifiedAt
        }
    }
}
