import Foundation
import GeneratedFilesCore

package extension GeneratedFileCacheStore {
    /// Returns the root cache directory URL for the given bucket, optionally creating it.
    func cacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        createIfNeeded: Bool
    ) -> URL? {
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let rootURL = cachesURL.appendingPathComponent(bucket.directoryName, isDirectory: true)
        if createIfNeeded {
            do {
                try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            } catch {
                GeneratedFilesLogger.error("[cacheRootURL] \(error.localizedDescription)")
                return nil
            }
        }
        return rootURL
    }

    /// Returns the per-key cache directory URL, creating intermediate directories as needed.
    /// - Throws: ``GeneratedFileStoreError/invalidCacheRoot`` if the root cannot be created.
    func cacheDirectoryURL(
        for cacheKey: String,
        bucket: GeneratedFileCacheBucket
    ) throws(GeneratedFileStoreError) -> URL {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: true) else {
            throw GeneratedFileStoreError.invalidCacheRoot
        }

        return rootURL.appendingPathComponent(sanitizedCacheKey(cacheKey), isDirectory: true)
    }

    /// Updates the modification date of the file at the given URL to the current time.
    func touchGeneratedFile(at fileURL: URL) {
        setItemModificationDate(Date(), atPath: fileURL.path, logContext: "touchGeneratedFile")
    }

    /// Deletes the entire cache directory for the given bucket.
    func clearCache(for bucket: GeneratedFileCacheBucket) {
        guard let rootURL = cacheRootURL(for: bucket, createIfNeeded: false) else {
            return
        }

        removeItemIfExists(at: rootURL, logContext: "clearCache")
    }

    /// Removes the temporary file previews directory.
    func cleanupTempPreviews() {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("file_previews", isDirectory: true)
        removeItemIfExists(at: tempDir, logContext: "cleanupTempPreviews")
    }

    /// Replaces path-unsafe characters in a cache key with underscores.
    func sanitizedCacheKey(_ cacheKey: String) -> String {
        cacheKey
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }

    /// Returns `true` if the URL points to an existing directory.
    func isDirectoryURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
