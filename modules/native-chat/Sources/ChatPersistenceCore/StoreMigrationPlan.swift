import Foundation

/// Strategy to apply when a persistent store migration fails.
public enum StoreRecoveryAction: String, Equatable, Sendable {
    /// Attempt to restore from the most recent backup.
    case restoreBackup
    /// Move the corrupt store aside and create a fresh one.
    case quarantineAndRebuild
    /// Discard the existing store without attempting a restore.
    case rebuildWithoutRestore
}

/// Describes a persistent store migration: which source versions are supported,
/// where backups are stored, and what to do if the migration fails.
public struct StoreMigrationPlan: Equatable, Sendable {
    /// The schema version this plan migrates to.
    public let targetVersion: String
    /// Source schema versions that can be upgraded to ``targetVersion``.
    public let supportedSourceVersions: Set<String>
    /// Directory name (relative to the store) where pre-migration backups are saved.
    public let backupDirectoryName: String
    /// Recovery strategy applied when migration fails.
    public let failureRecoveryAction: StoreRecoveryAction

    /// Creates a migration plan.
    public init(
        targetVersion: String,
        supportedSourceVersions: Set<String>,
        backupDirectoryName: String = "migration-backups",
        failureRecoveryAction: StoreRecoveryAction
    ) {
        self.targetVersion = targetVersion
        self.supportedSourceVersions = supportedSourceVersions
        self.backupDirectoryName = backupDirectoryName
        self.failureRecoveryAction = failureRecoveryAction
    }

    /// Returns `true` if `sourceVersion` is in ``supportedSourceVersions``.
    public func supportsUpgrade(from sourceVersion: String) -> Bool {
        supportedSourceVersions.contains(sourceVersion)
    }

    /// Computes the backup file URL for a given store URL and timestamp.
    public func backupURL(for storeURL: URL, timestamp: Date) -> URL {
        let backupFilename = storeURL.deletingPathExtension().lastPathComponent
            + "-"
            + PersistenceTimestampFormatter.storePathComponent(from: timestamp)

        return storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(backupDirectoryName, isDirectory: true)
            .appendingPathComponent(backupFilename)
            .appendingPathExtension(storeURL.pathExtension)
    }
}

/// Report produced after a store migration or recovery attempt.
public struct StoreRecoveryReport: Equatable, Sendable {
    /// The schema version of the store before migration, if known.
    public let sourceVersion: String?
    /// The schema version this migration targeted.
    public let targetVersion: String
    /// The URL of any backup created before migration.
    public let backupURL: URL?
    /// The recovery action that was applied, if migration failed.
    public let recoveryAction: StoreRecoveryAction?
    /// Whether the overall migration or recovery succeeded.
    public let succeeded: Bool

    /// Creates a recovery report.
    public init(
        sourceVersion: String?,
        targetVersion: String,
        backupURL: URL? = nil,
        recoveryAction: StoreRecoveryAction? = nil,
        succeeded: Bool
    ) {
        self.sourceVersion = sourceVersion
        self.targetVersion = targetVersion
        self.backupURL = backupURL
        self.recoveryAction = recoveryAction
        self.succeeded = succeeded
    }
}
