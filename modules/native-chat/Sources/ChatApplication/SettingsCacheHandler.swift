/// Handler protocol for generated-file cache operations used by the settings scene.
package protocol SettingsCacheHandler: Sendable {
    /// Returns the current size in bytes of the generated image cache.
    func refreshGeneratedImageCacheSize() async -> Int64
    /// Returns the current size in bytes of the generated document cache.
    func refreshGeneratedDocumentCacheSize() async -> Int64
    /// Clears the generated image cache and returns the new (zero) size.
    func clearGeneratedImageCache() async -> Int64
    /// Clears the generated document cache and returns the new (zero) size.
    func clearGeneratedDocumentCache() async -> Int64
}
