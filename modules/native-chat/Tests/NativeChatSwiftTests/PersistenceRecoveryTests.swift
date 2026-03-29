import ChatPersistenceCore
import ChatPersistenceSwiftData
import Foundation
import Testing

struct PersistenceRecoveryTests {
    @Test
    func `store migration plan computes backup URL in migration backup directory`() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("chat.sqlite")
        let timestamp = Date(timeIntervalSince1970: 1_742_000_000)
        let plan = StoreMigrationPlan(
            targetVersion: "5.3.0",
            supportedSourceVersions: ["5.2.0"],
            failureRecoveryAction: .restoreBackup
        )

        let backupURL = plan.backupURL(for: storeURL, timestamp: timestamp)

        #expect(plan.supportsUpgrade(from: "5.2.0"))
        #expect(backupURL.deletingLastPathComponent().lastPathComponent == "migration-backups")
        #expect(backupURL.pathExtension == "sqlite")
    }

    @Test
    func `persistence backup manager restore replaces existing store contents`() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let storeURL = tempDirectory.appendingPathComponent("chat.sqlite")
        let backupURL = tempDirectory.appendingPathComponent("chat-backup.sqlite")
        try Data("stale".utf8).write(to: storeURL)
        try Data("restored".utf8).write(to: backupURL)

        try PersistenceBackupManager.restore(from: backupURL, to: storeURL)

        let restoredData = try Data(contentsOf: storeURL)
        #expect(String(decoding: restoredData, as: UTF8.self) == "restored")
    }
}
