import Foundation

extension SettingsScreenStore {
    func refreshGeneratedImageCacheSize() async {
        generatedImageCacheSizeBytes = await FileDownloadService.shared.generatedImageCacheSize()
    }

    func refreshGeneratedDocumentCacheSize() async {
        generatedDocumentCacheSizeBytes = await FileDownloadService.shared.generatedDocumentCacheSize()
    }

    func clearGeneratedImageCache() async {
        guard !isClearingImageCache else { return }

        isClearingImageCache = true
        await FileDownloadService.shared.clearGeneratedImageCache()
        generatedImageCacheSizeBytes = await FileDownloadService.shared.generatedImageCacheSize()
        isClearingImageCache = false
        HapticService.shared.impact(.medium)
    }

    func clearGeneratedDocumentCache() async {
        guard !isClearingDocumentCache else { return }

        isClearingDocumentCache = true
        await FileDownloadService.shared.clearGeneratedDocumentCache()
        generatedDocumentCacheSizeBytes = await FileDownloadService.shared.generatedDocumentCacheSize()
        isClearingDocumentCache = false
        HapticService.shared.impact(.medium)
    }
}
