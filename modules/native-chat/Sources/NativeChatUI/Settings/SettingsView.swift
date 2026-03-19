import ChatPresentation
import SwiftUI

/// Main settings screen with API key, Cloudflare gateway, chat defaults, appearance, and cache management.
public struct SettingsView: View {
    @State private var credentials: SettingsCredentialsStore
    @State private var defaults: SettingsDefaultsStore
    @State private var cache: SettingsCacheStore
    private let about: SettingsAboutInfo

    /// Creates a settings view backed by the given presenter.
    @MainActor
    public init(viewModel: SettingsPresenter) {
        _credentials = State(initialValue: viewModel.credentials)
        _defaults = State(initialValue: viewModel.defaults)
        _cache = State(initialValue: viewModel.cache)
        about = viewModel.about
    }

    /// The settings form content and confirmation alerts for the settings flow.
    public var body: some View {
        let imageCacheFooter = cacheFooterText(
            description: String(
                localized: "Generated images are cached automatically so old download links still open later. Maximum cache size"
            ),
            limit: cache.generatedImageCacheLimitString
        )
        let documentCacheFooter = cacheFooterText(
            description: String(
                localized: """
                Generated PDFs and other files are cached automatically so old download links still open \
                or share later. Maximum cache size
                """
            ),
            limit: cache.generatedDocumentCacheLimitString
        )

        NavigationStack {
            Form {
                SettingsAPIConfigurationSection(viewModel: credentials)
                SettingsCloudflareSection(
                    credentials: credentials,
                    defaults: defaults
                )
                SettingsChatDefaultsSection(viewModel: defaults)
                SettingsAppearanceSection(viewModel: defaults)
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
                SettingsAboutSection(
                    appVersionString: about.appVersionString,
                    platformString: about.platformString
                )
            }
            .navigationTitle(String(localized: "Settings"))
            .task {
                await cache.refreshAll()
            }
            .alert(String(localized: "API Key Saved"), isPresented: saveConfirmationBinding) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Your OpenAI API key has been saved to Keychain."))
            }
        }
    }

    private func cacheFooterText(description: String, limit: String) -> String {
        "\(description): \(limit)."
    }

    private var saveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { credentials.saveConfirmation },
            set: { credentials.saveConfirmation = $0 }
        )
    }
}
