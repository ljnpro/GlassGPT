import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI
import UIKit

struct SettingsAPIConfigurationSection: View {
    @Bindable var viewModel: SettingsCredentialsStore

    var body: some View {
        Section {
            SecureField(String(localized: "sk-proj-..."), text: $viewModel.apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(String(localized: "API key input"))
                .accessibilityIdentifier("settings.apiKey")

            if let isValid = viewModel.isAPIKeyValid {
                HStack {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(isValid ? .green : .red)
                        .accessibilityHidden(true)
                    Text(isValid ? String(localized: "API key is valid") : String(localized: "API key is invalid"))
                        .font(.caption)
                        .foregroundStyle(isValid ? .green : .red)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(isValid ? String(localized: "API key is valid") : String(localized: "API key is invalid"))
                .accessibilityIdentifier("settings.apiKeyStatus")
            }

            HStack {
                Button(String(localized: "Validate")) {
                    Task { @MainActor in
                        await viewModel.validateAPIKey()
                    }
                }
                .buttonStyle(.glass)
                .disabled(viewModel.apiKey.isEmpty || viewModel.isValidating)
                .accessibilityLabel(String(localized: "Validate API key"))
                .accessibilityIdentifier("settings.validateAPIKey")

                Spacer()

                Button(String(localized: "Clear"), role: .destructive) {
                    viewModel.clearAPIKey()
                }
                .buttonStyle(.glass)
                .tint(.red)
                .accessibilityLabel(String(localized: "Clear API key"))
                .accessibilityIdentifier("settings.clearAPIKey")

                Button(String(localized: "Save")) {
                    viewModel.saveAPIKey()
                }
                .buttonStyle(.glassProminent)
                .disabled(viewModel.apiKey.isEmpty)
                .accessibilityLabel(String(localized: "Save API key"))
                .accessibilityIdentifier("settings.saveAPIKey")
            }
        } header: {
            Text(String(localized: "API Configuration"))
        } footer: {
            Text(String(localized: "Your API key is stored securely in the device Keychain."))
        }
    }
}

struct SettingsCloudflareSection: View {
    @Bindable var credentials: SettingsCredentialsStore
    @Bindable var defaults: SettingsDefaultsStore

    var canCheckConnection: Bool {
        switch credentials.cloudflareHealthStatus {
        case .gatewayUnavailable, .invalidGatewayURL:
            false
        default:
            true
        }
    }

    var body: some View {
        Section {
            Toggle(String(localized: "Enable Cloudflare Gateway"), isOn: $defaults.cloudflareEnabled)
                .accessibilityLabel(String(localized: "Enable Cloudflare Gateway"))
                .accessibilityIdentifier("settings.cloudflare")

            if defaults.cloudflareEnabled {
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Connection Status"))
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    if credentials.isCheckingCloudflareHealth {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Checking connection"))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(String(localized: "Cloudflare connection status") + ": \(statusText)")
                .accessibilityIdentifier("settings.cloudflareStatus")

                Button(String(localized: "Check Connection")) {
                    Task { @MainActor in
                        await credentials.checkCloudflareHealth()
                    }
                }
                .buttonStyle(.glass)
                .disabled(credentials.isCheckingCloudflareHealth || !canCheckConnection)
                .accessibilityLabel(String(localized: "Check Cloudflare connection"))
                .accessibilityIdentifier("settings.checkConnection")
            }
        } header: {
            Text(String(localized: "Cloudflare Gateway"))
        } footer: {
            Text(String(localized: "Route API requests through Cloudflare's global edge network for improved reliability and analytics."))
        }
    }

    private var statusColor: Color {
        switch credentials.cloudflareHealthStatus {
        case .connected:
            .green
        case .checking:
            .yellow
        case .missingAPIKey:
            .orange
        case .gatewayUnavailable, .unknown:
            .gray
        case .invalidGatewayURL, .remoteError:
            .red
        }
    }

    private var statusText: String {
        switch credentials.cloudflareHealthStatus {
        case .connected:
            String(localized: "Connected")
        case .checking:
            String(localized: "Checking connection…")
        case .gatewayUnavailable:
            String(localized: "Gateway unavailable in this build")
        case .missingAPIKey:
            String(localized: "No API key configured")
        case .invalidGatewayURL:
            String(localized: "Invalid gateway URL")
        case let .remoteError(message):
            message
        case .unknown:
            String(localized: "Not checked")
        }
    }
}

struct SettingsChatDefaultsSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section {
            Toggle(String(localized: "Default Pro Mode"), isOn: Binding(
                get: { viewModel.defaultProModeEnabled },
                set: { viewModel.defaultProModeEnabled = $0 }
            ))
            .accessibilityLabel(String(localized: "Default Pro Mode"))
            .accessibilityIdentifier("settings.defaultProMode")

            Toggle(String(localized: "Default Background Mode"), isOn: $viewModel.defaultBackgroundModeEnabled)
                .accessibilityLabel(String(localized: "Default Background Mode"))
                .accessibilityIdentifier("settings.defaultBackgroundMode")

            Toggle(String(localized: "Default Flex Mode"), isOn: Binding(
                get: { viewModel.defaultFlexModeEnabled },
                set: { viewModel.defaultFlexModeEnabled = $0 }
            ))
            .accessibilityLabel(String(localized: "Default Flex Mode"))
            .accessibilityIdentifier("settings.defaultFlexMode")

            Picker(String(localized: "Reasoning Effort"), selection: $viewModel.defaultEffort) {
                ForEach(viewModel.availableDefaultEfforts) { effort in
                    Text(effort.displayName).tag(effort)
                }
            }
            .accessibilityLabel(String(localized: "Default reasoning effort"))
            .accessibilityIdentifier("settings.defaultEffort")
        } header: {
            Text(String(localized: "Chat Defaults"))
        } footer: {
            Text(
                String(
                    localized: """
                    These defaults are applied only when you start a new chat. Existing conversations keep \
                    their own model, background, and pricing settings.
                    """
                )
            )
        }
    }
}

struct SettingsAppearanceSection: View {
    @Bindable var viewModel: SettingsDefaultsStore

    var body: some View {
        Section(String(localized: "Appearance")) {
            Picker(String(localized: "Theme"), selection: $viewModel.appTheme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(String(localized: "App theme"))
            .accessibilityIdentifier("settings.themePicker")
            .accessibilityValue(viewModel.appTheme.displayName)

            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle(String(localized: "Haptic Feedback"), isOn: $viewModel.hapticEnabled)
                    .accessibilityLabel(String(localized: "Haptic feedback"))
                    .accessibilityIdentifier("settings.haptics")
            }
        }
    }
}
