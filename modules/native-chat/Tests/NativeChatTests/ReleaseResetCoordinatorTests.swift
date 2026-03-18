import Foundation
import XCTest
import ChatPersistenceCore

final class ReleaseResetCoordinatorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-reset-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    func testPerformIfNeededDeletesStoreCachePreviewAndClearsDefaults() throws {
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

        let defaultsSuite = "release.reset.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
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

        XCTAssertTrue(didReset)
        XCTAssertEqual(defaults.string(forKey: ReleaseResetCoordinator.resetMarkerKey), ReleaseResetCoordinator.targetVersion)
        XCTAssertNil(defaults.object(forKey: "appTheme"))
        XCTAssertNil(defaults.object(forKey: "cloudflareGatewayEnabled"))
        XCTAssertEqual(resetService, defaultsSuite)
        XCTAssertFalse(FileManager.default.fileExists(atPath: appSupport.appendingPathComponent("default.store").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredStores.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("generated-images").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: caches.appendingPathComponent("generated-documents").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: previewDirectory.path))
    }

    func testPerformIfNeededIsIdempotentForTargetVersion() throws {
        let defaultsSuite = "release.reset.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
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

        XCTAssertFalse(didReset)
        XCTAssertEqual(resetCallCount, 0)
    }
}
