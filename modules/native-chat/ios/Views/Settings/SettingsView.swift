import SwiftUI
import UIKit

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = State(initialValue: viewModel)
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
                Section {
                    SecureField("sk-proj-...", text: $viewModel.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let isValid = viewModel.isAPIKeyValid {
                        HStack {
                            Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(isValid ? .green : .red)
                            Text(isValid ? "API key is valid" : "API key is invalid")
                                .font(.caption)
                                .foregroundStyle(isValid ? .green : .red)
                        }
                    }

                    HStack {
                        Button("Validate") {
                            Task { @MainActor in
                                await viewModel.validateAPIKey()
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(viewModel.apiKey.isEmpty || viewModel.isValidating)

                        Spacer()

                        Button("Clear", role: .destructive) {
                            viewModel.clearAPIKey()
                        }
                        .buttonStyle(.glass)
                        .tint(.red)

                        Button("Save") {
                            viewModel.saveAPIKey()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(viewModel.apiKey.isEmpty)
                    }
                } header: {
                    Text("API Configuration")
                } footer: {
                    Text("Your API key is stored securely in the device Keychain.")
                }

                Section {
                    Toggle("Enable Cloudflare Gateway", isOn: $viewModel.cloudflareEnabled)

                    if viewModel.cloudflareEnabled {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(cloudflareStatusColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connection Status")
                                Text(cloudflareStatusText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            if viewModel.isCheckingCloudflareHealth {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Button("Check Connection") {
                            Task { @MainActor in
                                await viewModel.checkCloudflareHealth()
                            }
                        }
                        .buttonStyle(.glass)
                        .disabled(viewModel.isCheckingCloudflareHealth)
                    }
                } header: {
                    Text("Cloudflare Gateway")
                } footer: {
                    Text("Route API requests through Cloudflare's global edge network for improved reliability and analytics.")
                }

                Section {
                    Toggle("Default Pro Mode", isOn: Binding(
                        get: { viewModel.defaultProModeEnabled },
                        set: { viewModel.defaultProModeEnabled = $0 }
                    ))

                    Toggle("Default Background Mode", isOn: $viewModel.defaultBackgroundModeEnabled)

                    Toggle("Default Flex Mode", isOn: Binding(
                        get: { viewModel.defaultFlexModeEnabled },
                        set: { viewModel.defaultFlexModeEnabled = $0 }
                    ))

                    Picker("Reasoning Effort", selection: $viewModel.defaultEffort) {
                        ForEach(viewModel.availableDefaultEfforts) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                } header: {
                    Text("Chat Defaults")
                } footer: {
                    Text("These defaults are applied only when you start a new chat. Existing conversations keep their own model, background, and pricing settings.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $viewModel.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Toggle("Haptic Feedback", isOn: $viewModel.hapticEnabled)
                    }
                }

                Section {
                    LabeledContent("Used", value: viewModel.generatedImageCacheSizeString)

                    Button(role: .destructive) {
                        Task { @MainActor in
                            await viewModel.clearGeneratedImageCache()
                        }
                    } label: {
                        HStack {
                            if viewModel.isClearingImageCache {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Clear Image Cache")
                        }
                    }
                    .disabled(viewModel.isClearingImageCache || viewModel.generatedImageCacheSizeBytes == 0)
                } header: {
                    Text("Image Cache")
                } footer: {
                    Text("Generated images are cached automatically so old download links still open later. Maximum cache size: \(viewModel.generatedImageCacheLimitString).")
                }

                Section {
                    LabeledContent("Used", value: viewModel.generatedDocumentCacheSizeString)

                    Button(role: .destructive) {
                        Task { @MainActor in
                            await viewModel.clearGeneratedDocumentCache()
                        }
                    } label: {
                        HStack {
                            if viewModel.isClearingDocumentCache {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Clear Document Cache")
                        }
                    }
                    .disabled(viewModel.isClearingDocumentCache || viewModel.generatedDocumentCacheSizeBytes == 0)
                } header: {
                    Text("Document Cache")
                } footer: {
                    Text("Generated PDFs and other files are cached automatically so old download links still open or share later. Maximum cache size: \(viewModel.generatedDocumentCacheLimitString).")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersionString)
                    LabeledContent("Platform", value: platformString)
                    LabeledContent("Engine", value: "SwiftUI")

                    if let supportURL = URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/") {
                        Link(destination: supportURL) {
                            HStack {
                                Text("Support Website")
                                Spacer()
                                Image(systemName: "safari")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
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
