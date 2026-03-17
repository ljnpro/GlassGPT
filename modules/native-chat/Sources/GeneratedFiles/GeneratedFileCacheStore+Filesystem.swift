import Foundation

extension GeneratedFileCacheStore {
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

    package func removeItemIfExists(at url: URL, logContext: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }

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

    package func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
            return nil
        }
    }

    package func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        do {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: path)
        } catch {
            GeneratedFilesLogger.error("[\(logContext)] \(error.localizedDescription)")
        }
    }
}
