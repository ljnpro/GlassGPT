import SwiftUI
import UIKit

struct SettingsView: View {
    @State private var viewModel: SettingsScreenStore
    private let appVersionStringOverride: String?

    @MainActor
    init(
        viewModel: SettingsScreenStore,
        appVersionStringOverride: String? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.appVersionStringOverride = appVersionStringOverride
    }

    @MainActor
    init(appVersionStringOverride: String? = nil) {
        _viewModel = State(initialValue: SettingsScreenStore())
        self.appVersionStringOverride = appVersionStringOverride
    }

    private var platformString: String {
        let device = UIDevice.current
        let osName: String

        switch device.userInterfaceIdiom {
        case .pad:
            osName = "iPadOS"
        default:
            osName = "iOS"
        }

        let version = device.systemVersion
        let majorVersion = Int(version.components(separatedBy: ".").first ?? "0") ?? 0

        if majorVersion >= 26 {
            return "\(osName) \(version) · Liquid Glass"
        } else {
            return "\(osName) \(version)"
        }
    }

    private var appVersionString: String {
        if let appVersionStringOverride {
            return appVersionStringOverride
        }

        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        return "\(shortVersion) (\(buildNumber))"
    }

    private var cloudflareStatusColor: Color {
        switch viewModel.cloudflareHealthStatus {
        case .connected:
            return .green
        case .checking:
            return .yellow
        case .error:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var cloudflareStatusText: String {
        switch viewModel.cloudflareHealthStatus {
        case .connected:
            return "Connected"
        case .checking:
            return "Checking connection…"
        case .error(let message):
            return message
        case .unknown:
            return "Not checked"
        }
    }

    var body: some View {
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
                    footerText: "Generated PDFs and other files are cached automatically so old download links still open or share later. Maximum cache size: \(viewModel.generatedDocumentCacheLimitString).",
                    isClearing: viewModel.isClearingDocumentCache,
                    hasCachedContent: viewModel.generatedDocumentCacheSizeBytes > 0,
                    clearLabel: "Clear Document Cache",
                    clearAction: {
                        await viewModel.clearGeneratedDocumentCache()
                    }
                )
                SettingsAboutSection(
                    appVersionString: appVersionString,
                    platformString: platformString
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
