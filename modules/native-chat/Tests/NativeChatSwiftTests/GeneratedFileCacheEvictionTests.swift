import Foundation
import GeneratedFilesCore
import Testing
@testable import GeneratedFilesCache

struct GeneratedFileCacheEvictionTests {
    private func makeTempCacheStore() -> (GeneratedFileCacheStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = GeneratedFileCacheStore(fileManager: .default, cacheRootOverride: root)
        return (store, root)
    }

    private func seedFile(
        store: GeneratedFileCacheStore,
        cacheKey: String,
        bucket: GeneratedFileCacheBucket,
        sizeBytes: Int,
        modifiedAt: Date = .now
    ) {
        let data = Data(repeating: 0xAA, count: sizeBytes)
        _ = try? store.storeGeneratedFile(
            data: data,
            filename: "\(cacheKey).bin",
            cacheKey: cacheKey,
            bucket: bucket
        )
        if let entry = store.existingCacheEntry(cacheKey: cacheKey, suggestedFilename: nil, bucket: bucket) {
            try? FileManager.default.setAttributes(
                [.modificationDate: modifiedAt],
                ofItemAtPath: entry.fileURL.path
            )
        }
    }

    @Test func `empty cache does not crash on trim`() {
        let (store, root) = makeTempCacheStore()
        defer { try? FileManager.default.removeItem(at: root) }

        store.trimCacheIfNeeded(for: .image, limitBytes: 100)
        #expect(store.cacheSize(for: .image) == 0)
    }

    @Test func `cache at exactly the limit is not evicted`() {
        let (store, root) = makeTempCacheStore()
        defer { try? FileManager.default.removeItem(at: root) }

        seedFile(store: store, cacheKey: "file1", bucket: .image, sizeBytes: 100)
        let sizeBeforeTrim = store.cacheSize(for: .image)

        store.trimCacheIfNeeded(for: .image, limitBytes: sizeBeforeTrim)
        #expect(store.cacheSize(for: .image) == sizeBeforeTrim)
    }

    @Test func `cache just over limit evicts oldest entry`() {
        let (store, root) = makeTempCacheStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let older = Date.now.addingTimeInterval(-60)
        let newer = Date.now

        seedFile(store: store, cacheKey: "old", bucket: .image, sizeBytes: 50, modifiedAt: older)
        seedFile(store: store, cacheKey: "new", bucket: .image, sizeBytes: 50, modifiedAt: newer)

        let totalBefore = store.cacheSize(for: .image)
        let limit = totalBefore - 1

        store.trimCacheIfNeeded(for: .image, limitBytes: limit)

        #expect(store.existingCacheEntry(cacheKey: "old", suggestedFilename: nil, bucket: .image) == nil)
        #expect(store.existingCacheEntry(cacheKey: "new", suggestedFilename: nil, bucket: .image) != nil)
    }

    @Test func `single large file exceeding limit is evicted`() {
        let (store, root) = makeTempCacheStore()
        defer { try? FileManager.default.removeItem(at: root) }

        seedFile(store: store, cacheKey: "big", bucket: .document, sizeBytes: 1000)
        store.trimCacheIfNeeded(for: .document, limitBytes: 100)

        #expect(store.cacheSize(for: .document) == 0)
    }

    @Test func `eviction preserves newest entries when multiple evicted`() {
        let (store, root) = makeTempCacheStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let base = Date.now.addingTimeInterval(-300)
        for index in 0 ..< 5 {
            seedFile(
                store: store,
                cacheKey: "f\(index)",
                bucket: .image,
                sizeBytes: 100,
                modifiedAt: base.addingTimeInterval(Double(index) * 60)
            )
        }

        // Keep only the newest 2 entries worth of space
        store.trimCacheIfNeeded(for: .image, limitBytes: 250)

        let remaining = store.cacheEntries(for: .image)
        #expect(remaining.count <= 3)
        // Oldest entries should be gone
        #expect(store.existingCacheEntry(cacheKey: "f0", suggestedFilename: nil, bucket: .image) == nil)
    }
}
