import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

struct SettingsAPIConfigurationSection: View {
    @Bindable var viewModel: SettingsPresenter

    var body: some View {
        Section {
            SecureField("sk-proj-...", text: $viewModel.apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("API key input")
                .accessibilityIdentifier("settings.apiKey")

            if let isValid = viewModel.isAPIKeyValid {
                HStack {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isValid ? .green : .red)
                        .accessibilityHidden(true)
                    Text(isValid ? "API key is valid" : "API key is invalid")
                        .font(.caption)
                        .foregroundStyle(isValid ? .green : .red)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isValid ? String(localized: "API key is valid") : String(localized: "API key is invalid"))
                .accessibilityIdentifier("settings.apiKeyStatus")
            }

            HStack {
                Button("Validate") {
                    Task { @MainActor in
                        await viewModel.validateAPIKey()
                    }
                }
                .buttonStyle(.glass)
                .disabled(viewModel.apiKey.isEmpty || viewModel.isValidating)
                .accessibilityLabel("Validate API key")
                .accessibilityIdentifier("settings.validateAPIKey")

                Spacer()

                Button("Clear", role: .destructive) {
                    viewModel.clearAPIKey()
                }
                .buttonStyle(.glass)
                .tint(.red)
                .accessibilityLabel("Clear API key")
                .accessibilityIdentifier("settings.clearAPIKey")

                Button("Save") {
                    viewModel.saveAPIKey()
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.apiKey.isEmpty)
                .accessibilityLabel("Save API key")
                .accessibilityIdentifier("settings.saveAPIKey")
            }
        } header: {
            Text("API Configuration")
        } footer: {
            Text("Your API key is stored securely in the device Keychain.")
        }
    }
}

struct SettingsCloudflareSection: View {
    @Bindable var viewModel: SettingsPresenter
    let statusColor: Color
    let statusText: String

    var canCheckConnection: Bool {
        switch viewModel.cloudflareHealthStatus {
        case .gatewayUnavailable, .invalidGatewayURL:
            return false
        default:
            return true
        }
    }

    var body: some View {
        Section {
            Toggle("Enable Cloudflare Gateway", isOn: $viewModel.cloudflareEnabled)
                .accessibilityLabel("Enable Cloudflare Gateway")
                .accessibilityIdentifier("settings.cloudflare")

            if viewModel.cloudflareEnabled {
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connection Status")
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    if viewModel.isCheckingCloudflareHealth {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Checking connection")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Cloudflare connection status: \(statusText)"))
                .accessibilityIdentifier("settings.cloudflareStatus")

                Button("Check Connection") {
                    Task { @MainActor in
                        await viewModel.checkCloudflareHealth()
                    }
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isCheckingCloudflareHealth || !canCheckConnection)
                .accessibilityLabel(String(localized: "Check Cloudflare connection"))
                .accessibilityIdentifier("settings.checkConnection")
            }
        } header: {
            Text("Cloudflare Gateway")
        } footer: {
            Text("Route API requests through Cloudflare's global edge network for improved reliability and analytics.")
        }
    }
}

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsPresenter

    var body: some View {
        Section {
            Toggle("Default Pro Mode", isOn: Binding(
                get: { viewModel.defaultProModeEnabled },
                set: { viewModel.defaultProModeEnabled = $0 }
            ))
            .accessibilityLabel("Default Pro Mode")
            .accessibilityIdentifier("settings.defaultProMode")

            Toggle("Default Background Mode", isOn: $viewModel.defaultBackgroundModeEnabled)
                .accessibilityLabel("Default Background Mode")
                .accessibilityIdentifier("settings.defaultBackgroundMode")

            Toggle("Default Flex Mode", isOn: Binding(
                get: { viewModel.defaultFlexModeEnabled },
                set: { viewModel.defaultFlexModeEnabled = $0 }
            ))
            .accessibilityLabel("Default Flex Mode")
            .accessibilityIdentifier("settings.defaultFlexMode")

            Picker("Reasoning Effort", selection: $viewModel.defaultEffort) {
                ForEach(viewModel.availableDefaultEfforts) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .accessibilityLabel("Default reasoning effort")
            .accessibilityIdentifier("settings.defaultEffort")
        } header: {
            Text("Chat Defaults")
        } footer: {
            // swiftlint:disable:next line_length
            Text("These defaults are applied only when you start a new chat. Existing conversations keep their own model, background, and pricing settings.")
        }
    }
}

struct SettingsAppearanceSection: View {
    @Bindable var viewModel: SettingsPresenter

    var body: some View {
        Section("Appearance") {
            Picker("Theme", selection: $viewModel.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("App theme")
            .accessibilityIdentifier("settings.themePicker")

            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle("Haptic Feedback", isOn: $viewModel.hapticEnabled)
                    .accessibilityLabel("Haptic feedback")
                    .accessibilityIdentifier("settings.haptics")
            }
        }
    }
}
