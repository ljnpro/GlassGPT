import ChatApplication
import GeneratedFilesInfra

@MainActor
struct SettingsCacheHandlerImpl: SettingsCacheHandler {
    let fileDownloadService: GeneratedFilesInfra.FileDownloadService

    func refreshGeneratedImageCacheSize() async -> Int64 {
        await fileDownloadService.generatedImageCacheSize()
    }

    func refreshGeneratedDocumentCacheSize() async -> Int64 {
        await fileDownloadService.generatedDocumentCacheSize()
    }

    func clearGeneratedImageCache() async -> Int64 {
        await fileDownloadService.clearGeneratedImageCache()
        return await fileDownloadService.generatedImageCacheSize()
    }

    func clearGeneratedDocumentCache() async -> Int64 {
        await fileDownloadService.clearGeneratedDocumentCache()
        return await fileDownloadService.generatedDocumentCacheSize()
    }
}
