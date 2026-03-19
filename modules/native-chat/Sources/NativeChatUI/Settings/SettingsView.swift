import ChatPresentation
import SwiftUI

/// Main settings screen with API key, Cloudflare gateway, chat defaults, appearance, and cache management.
public struct SettingsView: View {
    @State private var viewModel: SettingsPresenter

    @MainActor
    /// Creates a settings view backed by the given presenter.
    public init(viewModel: SettingsPresenter) {
        _viewModel = State(initialValue: viewModel)
    }

    private var cloudflareStatusColor: Color {
        switch viewModel.cloudflareHealthStatus {
        case .connected:
            return .green
        case .checking:
            return .yellow
        case .missingAPIKey:
            return .orange
        case .gatewayUnavailable:
            return .gray
        case .invalidGatewayURL, .remoteError:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var cloudflareStatusText: String {
        switch viewModel.cloudflareHealthStatus {
        case .connected:
            return String(localized: "Connected")
        case .checking:
            return String(localized: "Checking connection…")
        case .gatewayUnavailable:
            return String(localized: "Gateway unavailable in this build")
        case .missingAPIKey:
            return String(localized: "No API key configured")
        case .invalidGatewayURL:
            return String(localized: "Invalid gateway URL")
        case .remoteError(let message):
            return message
        case .unknown:
            return String(localized: "Not checked")
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                SettingsAPIConfigurationSection(viewModel: viewModel)
                SettingsCloudflareSection(
                    viewModel: viewModel,
                    statusColor: cloudflareStatusColor,
                    statusText: cloudflareStatusText
                )
                SettingsChatDefaultsSection(viewModel: viewModel)
                SettingsAppearanceSection(viewModel: viewModel)
                SettingsCacheSection(
                    title: "Image Cache",
                    usedValue: viewModel.generatedImageCacheSizeString,
                    // swiftlint:disable:next line_length
                    footerText: "Generated images are cached automatically so old download links still open later. Maximum cache size: \(viewModel.generatedImageCacheLimitString).",
                    isClearing: viewModel.isClearingImageCache,
                    hasCachedContent: viewModel.generatedImageCacheSizeBytes > 0,
                    clearLabel: "Clear Image Cache",
                    clearAction: {
                        await viewModel.clearGeneratedImageCache()
                    }
                )
                SettingsCacheSection(
                    title: "Document Cache",
                    usedValue: viewModel.generatedDocumentCacheSizeString,
                    // swiftlint:disable:next line_length
                    footerText: "Generated PDFs and other files are cached automatically so old download links still open or share later. Maximum cache size: \(viewModel.generatedDocumentCacheLimitString).",
                    isClearing: viewModel.isClearingDocumentCache,
                    hasCachedContent: viewModel.generatedDocumentCacheSizeBytes > 0,
                    clearLabel: "Clear Document Cache",
                    clearAction: {
                        await viewModel.clearGeneratedDocumentCache()
                    }
                )
                SettingsAboutSection(
                    appVersionString: viewModel.appVersionString,
                    platformString: viewModel.platformString
                )
            }
            .navigationTitle("Settings")
            .task {
                await viewModel.refreshGeneratedImageCacheSize()
                await viewModel.refreshGeneratedDocumentCacheSize()
            }
            .alert("API Key Saved", isPresented: $viewModel.saveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your OpenAI API key has been saved to Keychain.")
            }
        }
    }
}
