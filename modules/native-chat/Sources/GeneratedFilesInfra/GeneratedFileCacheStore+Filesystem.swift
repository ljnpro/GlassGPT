import Foundation

package extension GeneratedFileCacheStore {
    /// Builds a ``CachedEntry`` from a file URL if the file exists and has valid attributes.
    func cachedEntry(
        fileURL: URL,
        directoryURL: URL
    ) -> CachedEntry? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let attributes = itemAttributes(atPath: fileURL.path, logContext: "cachedEntry.attributes"),
              let fileSize = attributes[.size] as? NSNumber
        else {
            return nil
        }

        return CachedEntry(
            directoryURL: directoryURL,
            fileURL: fileURL,
            size: fileSize.int64Value,
            modifiedAt: (attributes[.modificationDate] as? Date) ?? .distantPast
        )
    }

    /// Sanitizes a candidate filename, optionally appending an inferred extension if none is present.
    func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
        guard let candidate else { return nil }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = URL(fileURLWithPath: trimmed).lastPathComponent
        guard !sanitized.isEmpty else { return nil }

        if !URL(fileURLWithPath: sanitized).pathExtension.isEmpty {
            return sanitized
        }

        if let inferredExtension, !inferredExtension.isEmpty {
            return "\(sanitized).\(inferredExtension)"
        }

        return sanitized
    }

    /// Removes the item at the given URL if it exists, logging errors with the provided context.
    func removeItemIfExists(at url: URL, logContext: String) {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            // Item was already removed — not an error.
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }

    /// Returns the contents of the directory at the given URL, or an empty array on failure.
    func directoryContents(at url: URL, logContext: String) -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        do {
            return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
            return []
        }
    }

    /// Returns the file attributes at the given path, or `nil` on failure.
    func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
            return nil
        }
    }

    /// Sets the modification date for the item at the given path.
    func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        do {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }
}
