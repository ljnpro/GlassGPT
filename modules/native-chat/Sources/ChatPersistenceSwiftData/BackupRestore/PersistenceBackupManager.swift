import Foundation

/// Manages backup and restore of the SwiftData SQLite store.
public enum PersistenceBackupManager {
    private static var backupDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChatBackups", isDirectory: true)
    }

    /// Creates a timestamped backup of the current SwiftData store file.
    /// - Parameter storeURL: The URL of the active SQLite store.
    /// - Returns: The URL of the backup file.
    public static func backup(storeURL: URL) throws -> URL {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: backupDirectory.path) {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = backupDirectory
            .appendingPathComponent("chat-backup-\(timestamp).sqlite")
        try fileManager.copyItem(at: storeURL, to: backupURL)
        return backupURL
    }

    /// Restores a previously backed-up store file.
    /// - Parameters:
    ///   - backupURL: The URL of the backup to restore.
    ///   - storeURL: The URL of the active SQLite store to replace.
    public static func restore(from backupURL: URL, to storeURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: storeURL.path) {
            try fileManager.removeItem(at: storeURL)
        }
        try fileManager.copyItem(at: backupURL, to: storeURL)
    }

    private static func creationDate(for url: URL) -> Date {
        do {
            let values = try url.resourceValues(forKeys: [.creationDateKey])
            return values.creationDate ?? .distantPast
        } catch {
            return .distantPast
        }
    }

    /// Lists all available backup files, newest first.
    public static func listBackups() -> [URL] {
        let fileManager = FileManager.default
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: backupDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            return []
        }
        return contents
            .filter { $0.pathExtension == "sqlite" }
            .sorted { lhs, rhs in
                let lhsDate = creationDate(for: lhs)
                let rhsDate = creationDate(for: rhs)
                return lhsDate > rhsDate
            }
    }
}
