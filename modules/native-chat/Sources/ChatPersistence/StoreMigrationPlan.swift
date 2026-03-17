import Foundation

public enum StoreRecoveryAction: String, Equatable, Sendable {
    case restoreBackup
    case quarantineAndRebuild
    case rebuildWithoutRestore
}

public struct StoreMigrationPlan: Equatable, Sendable {
    public let targetVersion: String
    public let supportedSourceVersions: Set<String>
    public let backupDirectoryName: String
    public let failureRecoveryAction: StoreRecoveryAction

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

    public func supportsUpgrade(from sourceVersion: String) -> Bool {
        supportedSourceVersions.contains(sourceVersion)
    }

    public func backupURL(for storeURL: URL, timestamp: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let backupFilename = storeURL.deletingPathExtension().lastPathComponent + "-" + formatter.string(from: timestamp)

        return storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(backupDirectoryName, isDirectory: true)
            .appendingPathComponent(backupFilename)
            .appendingPathExtension(storeURL.pathExtension)
    }
}

public struct StoreRecoveryReport: Equatable, Sendable {
    public let sourceVersion: String?
    public let targetVersion: String
    public let backupURL: URL?
    public let recoveryAction: StoreRecoveryAction?
    public let succeeded: Bool

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
