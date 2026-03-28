import ChatPresentation
import SwiftUI

struct SettingsCacheManagementView: View {
    @Bindable var cache: SettingsCacheStore
    let imageCacheFooter: String
    let documentCacheFooter: String

    var body: some View {
        Form {
            SettingsCacheSection(
                title: String(localized: "Image Cache"),
                usedValue: cache.generatedImageCacheSizeString,
                footerText: imageCacheFooter,
                isClearing: cache.isClearingImageCache,
                hasCachedContent: cache.generatedImageCacheSizeBytes > 0,
                clearLabel: String(localized: "Clear Image Cache"),
                clearAction: {
                    await cache.clearGeneratedImageCache()
                }
            )
            SettingsCacheSection(
                title: String(localized: "Document Cache"),
                usedValue: cache.generatedDocumentCacheSizeString,
                footerText: documentCacheFooter,
                isClearing: cache.isClearingDocumentCache,
                hasCachedContent: cache.generatedDocumentCacheSizeBytes > 0,
                clearLabel: String(localized: "Clear Document Cache"),
                clearAction: {
                    await cache.clearGeneratedDocumentCache()
                }
            )
        }
        .listSectionSpacing(.compact)
        .navigationTitle(String(localized: "Cache"))
        .task {
            await cache.refreshAll()
        }
    }
}
