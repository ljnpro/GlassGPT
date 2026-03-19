import Foundation

extension GeneratedFileCacheStore {
    /// Builds a ``CachedEntry`` from a file URL if the file exists and has valid attributes.
    package func cachedEntry(
        fileURL: URL,
        directoryURL: URL
    ) -> CachedEntry? {
        guard fileManager.fileExists(atPath: fileURL.path),
              let attributes = itemAttributes(atPath: fileURL.path, logContext: "cachedEntry.attributes"),
              let fileSize = attributes[.size] as? NSNumber else {
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
    package func normalizedFilename(_ candidate: String?, inferredExtension: String?) -> String? {
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
    package func removeItemIfExists(at url: URL, logContext: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }

    /// Returns the contents of the directory at the given URL, or an empty array on failure.
    package func directoryContents(at url: URL, logContext: String) -> [URL] {
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
    package func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
            return nil
        }
    }

    /// Sets the modification date for the item at the given path.
    package func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        do {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }
}
