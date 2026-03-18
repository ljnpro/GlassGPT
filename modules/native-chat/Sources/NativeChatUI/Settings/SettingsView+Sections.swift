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
                .accessibilityIdentifier("settings.apiKey")

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
                    }
                }

                Button("Check Connection") {
                    Task { @MainActor in
                        await viewModel.checkCloudflareHealth()
                    }
                }
                .buttonStyle(.glass)
                .disabled(viewModel.isCheckingCloudflareHealth || !canCheckConnection)
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
            .accessibilityIdentifier("settings.themePicker")

            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle("Haptic Feedback", isOn: $viewModel.hapticEnabled)
                    .accessibilityIdentifier("settings.haptics")
            }
        }
    }
}
