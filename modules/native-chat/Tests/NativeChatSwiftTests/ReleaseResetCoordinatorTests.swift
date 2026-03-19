import ChatPersistenceCore
import Foundation
import Testing

struct ReleaseResetCoordinatorTests {
    private var tempRoot: URL

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-reset-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    @Test func `perform if needed deletes store and recovered stores`() throws {
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let directories = try makeResetDirectories()

        let result = try performReset(
            appSupport: directories.appSupport,
            caches: directories.caches,
            temp: directories.temp
        )

        #expect(result.didReset)
        #expect(
            result.defaults.string(forKey: ReleaseResetCoordinator.resetMarkerKey)
                == ReleaseResetCoordinator.targetVersion
        )
        #expect(result.defaults.object(forKey: "appTheme") == nil)
        #expect(result.defaults.object(forKey: "cloudflareGatewayEnabled") == nil)
        #expect(result.resetService == result.suiteName)
        #expect(!FileManager.default.fileExists(
            atPath: directories.appSupport.appendingPathComponent("default.store").path
        ))
        #expect(!FileManager.default.fileExists(atPath: directories.recoveredStores.path))
    }

    @Test func `perform if needed deletes caches and preview directories`() throws {
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let directories = try makeResetDirectories()

        let result = try performReset(
            appSupport: directories.appSupport,
            caches: directories.caches,
            temp: directories.temp
        )

        #expect(result.didReset)
        #expect(!FileManager.default.fileExists(
            atPath: directories.caches.appendingPathComponent("generated-images").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: directories.caches.appendingPathComponent("generated-documents").path
        ))
        #expect(!FileManager.default.fileExists(atPath: directories.previewDirectory.path))
    }

    @Test func `perform if needed is idempotent for target version`() throws {
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let defaultsSuite = "release.reset.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.set(ReleaseResetCoordinator.targetVersion, forKey: ReleaseResetCoordinator.resetMarkerKey)
        var resetCallCount = 0

        let didReset = ReleaseResetCoordinator.performIfNeeded(
            userDefaults: defaults,
            bundleIdentifier: defaultsSuite,
            applicationSupportDirectory: tempRoot,
            cachesDirectory: tempRoot,
            temporaryDirectory: tempRoot,
            apiKeyReset: { _ in
                resetCallCount += 1
            }
        )

        #expect(!didReset)
        #expect(resetCallCount == 0)
    }
}

// MARK: - Test Helpers

private extension ReleaseResetCoordinatorTests {
    struct ResetDirectories {
        let appSupport: URL
        let caches: URL
        let temp: URL
        let recoveredStores: URL
        let previewDirectory: URL
    }

    struct ResetResult {
        let didReset: Bool
        let defaults: UserDefaults
        let suiteName: String
        let resetService: String?
    }

    func makeResetDirectories() throws -> ResetDirectories {
        let appSupport = tempRoot.appendingPathComponent("Application Support", isDirectory: true)
        let caches = tempRoot.appendingPathComponent("Caches", isDirectory: true)
        let temp = tempRoot.appendingPathComponent("Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

        for filename in ["default.store", "default.store-shm", "default.store-wal"] {
            FileManager.default.createFile(
                atPath: appSupport.appendingPathComponent(filename).path,
                contents: Data("x".utf8)
            )
        }

        let recoveredStores = appSupport
            .appendingPathComponent("NativeChat", isDirectory: true)
            .appendingPathComponent("RecoveredStores", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveredStores, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: recoveredStores.appendingPathComponent("stale.store").path,
            contents: Data("x".utf8)
        )

        for directory in ["generated-images", "generated-documents"] {
            let directoryURL = caches.appendingPathComponent(directory, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            FileManager.default.createFile(
                atPath: directoryURL.appendingPathComponent("artifact.bin").path,
                contents: Data("x".utf8)
            )
        }

        let previewDirectory = temp.appendingPathComponent("file_previews", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: previewDirectory.appendingPathComponent("preview.bin").path,
            contents: Data("x".utf8)
        )

        return ResetDirectories(
            appSupport: appSupport,
            caches: caches,
            temp: temp,
            recoveredStores: recoveredStores,
            previewDirectory: previewDirectory
        )
    }

    func performReset(appSupport: URL, caches: URL, temp: URL) throws -> ResetResult {
        let defaultsSuite = "release.reset.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defaults.set("dark", forKey: "appTheme")
        defaults.set(true, forKey: "cloudflareGatewayEnabled")
        var resetService: String?

        let didReset = ReleaseResetCoordinator.performIfNeeded(
            userDefaults: defaults,
            bundleIdentifier: defaultsSuite,
            applicationSupportDirectory: appSupport,
            cachesDirectory: caches,
            temporaryDirectory: temp,
            apiKeyReset: { service in
                resetService = service
            }
        )

        return ResetResult(
            didReset: didReset,
            defaults: defaults,
            suiteName: defaultsSuite,
            resetService: resetService
        )
    }
}
