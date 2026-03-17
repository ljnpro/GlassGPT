import Foundation

extension GeneratedFileCacheStore {
    func cachedEntry(
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

    func removeItemIfExists(at url: URL, logContext: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
        }
    }

    func directoryContents(at url: URL, logContext: String) -> [URL] {
        do {
            return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
            return []
        }
    }

    func itemAttributes(atPath path: String, logContext: String) -> [FileAttributeKey: Any]? {
        do {
            return try fileManager.attributesOfItem(atPath: path)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
            return nil
        }
    }

    func setItemModificationDate(_ date: Date, atPath path: String, logContext: String) {
        do {
            try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: path)
        } catch {
            Loggers.files.error("[\(logContext)] \(error.localizedDescription)")
        }
    }
}
