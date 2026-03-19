import Foundation
import GeneratedFilesCore
import Testing
@testable import NativeChatComposition

// MARK: - Generated File Cache Tests

extension SettingsScreenStoreTests {
    @Test func refreshAndClearGeneratedCachesTrackFilesystemState() async throws {
        Self.clearGeneratedCacheRoots()
        defer { Self.clearGeneratedCacheRoots() }

        let imageBytes = Data("image-cache".utf8)
        let documentBytes = Data("document-cache".utf8)
        try Self.seedGeneratedCacheFile(
            bucket: .image,
            directoryName: UUID().uuidString,
            filename: "chart.png",
            data: imageBytes
        )
        try Self.seedGeneratedCacheFile(
            bucket: .document,
            directoryName: UUID().uuidString,
            filename: "report.pdf",
            data: documentBytes
        )

        let store = makeTestSettingsScreenStore()

        await store.refreshGeneratedImageCacheSize()
        await store.refreshGeneratedDocumentCacheSize()

        #expect(store.generatedImageCacheSizeBytes == Int64(imageBytes.count))
        #expect(store.generatedDocumentCacheSizeBytes == Int64(documentBytes.count))
        #expect(!store.isClearingImageCache)
        #expect(!store.isClearingDocumentCache)

        await store.clearGeneratedImageCache()
        await store.clearGeneratedDocumentCache()

        #expect(store.generatedImageCacheSizeBytes == 0)
        #expect(store.generatedDocumentCacheSizeBytes == 0)
        #expect(!store.isClearingImageCache)
        #expect(!store.isClearingDocumentCache)
    }
}

private extension SettingsScreenStoreTests {
    nonisolated static func clearGeneratedCacheRoots(fileManager: FileManager = .default) {
        for bucket in GeneratedFileCacheBucket.allCases {
            let rootURL = generatedCacheRootURL(for: bucket, fileManager: fileManager)
            try? fileManager.removeItem(at: rootURL)
        }
    }

    nonisolated static func seedGeneratedCacheFile(
        bucket: GeneratedFileCacheBucket,
        directoryName: String,
        filename: String,
        data: Data,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = generatedCacheRootURL(for: bucket, fileManager: fileManager)
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: directoryURL.appendingPathComponent(filename))
    }

    nonisolated static func generatedCacheRootURL(
        for bucket: GeneratedFileCacheBucket,
        fileManager: FileManager
    ) -> URL {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return cachesURL.appendingPathComponent(bucket.directoryName, isDirectory: true)
    }
}
