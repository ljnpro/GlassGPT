import ChatPresentation
import SwiftUI
import UIKit

enum SettingsFocusedField: Hashable {
    case apiKey
}

struct SettingsAPIKeyFieldFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let nextFrame = nextValue()
        if !nextFrame.isNull {
            value = nextFrame
        }
    }
}

@MainActor
private enum SettingsKeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Main settings screen with API key, Cloudflare gateway, chat defaults, appearance, and cache management.
public struct SettingsView: View {
    @State private var credentials: SettingsCredentialsStore
    @State private var defaults: SettingsDefaultsStore
    @State private var cache: SettingsCacheStore
    @State private var apiKeyFieldFrame: CGRect = .null
    @FocusState private var focusedField: SettingsFocusedField?
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
                SettingsAPIConfigurationSection(
                    viewModel: credentials,
                    focusedField: $focusedField,
                    dismissKeyboard: dismissAPIKeyKeyboard
                )
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
            .coordinateSpace(name: "settingsForm")
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("settings.form")
            .onPreferenceChange(SettingsAPIKeyFieldFramePreferenceKey.self) { apiKeyFieldFrame = $0 }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard focusedField == .apiKey,
                          !apiKeyFieldFrame.contains(value.location)
                    else {
                        return
                    }

                    dismissAPIKeyKeyboard()
                },
                including: focusedField == .apiKey ? .all : .none
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { _ in
                    guard focusedField == .apiKey else { return }
                    dismissAPIKeyKeyboard()
                },
                including: focusedField == .apiKey ? .all : .none
            )
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

    private func dismissAPIKeyKeyboard() {
        focusedField = nil
        SettingsKeyboardDismisser.dismiss()
    }

    private var saveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { credentials.saveConfirmation },
            set: { credentials.saveConfirmation = $0 }
        )
    }
}
