import ChatPersistenceCore
import Foundation
import Testing
@testable import NativeChatUITestSupport

struct UITestEnvironmentResetTests {
    @Test func `performIfRequested clears persisted state when launch argument is present`() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applicationSupportDirectory = rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let cachesDirectory = rootURL.appendingPathComponent("Caches", isDirectory: true)
        let temporaryDirectory = rootURL.appendingPathComponent("Temporary", isDirectory: true)
        let bundleIdentifier = "GlassGPT.UITestReset.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: bundleIdentifier))
        defer {
            userDefaults.removePersistentDomain(forName: bundleIdentifier)
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cachesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: applicationSupportDirectory.appendingPathComponent("default.store").path, contents: Data())
        try fileManager.createDirectory(
            at: cachesDirectory.appendingPathComponent("generated-images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporaryDirectory.appendingPathComponent("file_previews", isDirectory: true),
            withIntermediateDirectories: true
        )
        userDefaults.setPersistentDomain(["hasAcceptedDataSharing": true], forName: bundleIdentifier)
        var resetServices: [String] = []

        let didReset = UITestEnvironmentReset.performIfRequested(
            arguments: [UITestEnvironmentReset.launchArgument],
            bundleIdentifier: bundleIdentifier,
            userDefaults: userDefaults,
            applicationSupportDirectory: applicationSupportDirectory,
            cachesDirectory: cachesDirectory,
            temporaryDirectory: temporaryDirectory,
            fileManager: fileManager,
            resetCredentials: { resetServices.append($0) }
        )

        #expect(didReset)
        #expect(!fileManager.fileExists(atPath: applicationSupportDirectory.appendingPathComponent("default.store").path))
        #expect(!fileManager.fileExists(atPath: cachesDirectory.appendingPathComponent("generated-images").path))
        #expect(!fileManager.fileExists(atPath: temporaryDirectory.appendingPathComponent("file_previews").path))
        #expect((userDefaults.persistentDomain(forName: bundleIdentifier) ?? [:]).isEmpty)
        #expect(userDefaults.string(forKey: ReleaseResetCoordinator.resetMarkerKey) == nil)
        #expect(resetServices == [KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: bundleIdentifier)])
    }

    @Test func `performIfRequested without launch argument leaves persisted state untouched`() throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let applicationSupportDirectory = rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let bundleIdentifier = "GlassGPT.UITestReset.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: bundleIdentifier))
        defer {
            userDefaults.removePersistentDomain(forName: bundleIdentifier)
            try? fileManager.removeItem(at: rootURL)
        }

        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        fileManager.createFile(atPath: applicationSupportDirectory.appendingPathComponent("default.store").path, contents: Data())
        userDefaults.setPersistentDomain(["hasAcceptedDataSharing": true], forName: bundleIdentifier)
        var resetServices: [String] = []

        let didReset = UITestEnvironmentReset.performIfRequested(
            arguments: [],
            bundleIdentifier: bundleIdentifier,
            userDefaults: userDefaults,
            applicationSupportDirectory: applicationSupportDirectory,
            fileManager: fileManager,
            resetCredentials: { resetServices.append($0) }
        )

        #expect(!didReset)
        #expect(fileManager.fileExists(atPath: applicationSupportDirectory.appendingPathComponent("default.store").path))
        #expect(userDefaults.bool(forKey: "hasAcceptedDataSharing"))
        #expect(resetServices.isEmpty)
    }
}
