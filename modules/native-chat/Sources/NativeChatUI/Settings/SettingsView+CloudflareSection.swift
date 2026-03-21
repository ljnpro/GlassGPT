import ChatDomain
import ChatPresentation
import ChatUIComponents
import SwiftUI

struct SettingsCloudflareSection: View {
    @Bindable var credentials: SettingsCredentialsStore
    @Bindable var defaults: SettingsDefaultsStore
    let focusedField: FocusState<SettingsFocusedField?>.Binding

    var body: some View {
        Section {
            Toggle(String(localized: "Enable Cloudflare Gateway"), isOn: $defaults.cloudflareEnabled)
                .accessibilityLabel(String(localized: "Enable Cloudflare Gateway"))
                .accessibilityIdentifier("settings.cloudflare")

            if defaults.cloudflareEnabled {
                Picker(
                    String(localized: "Gateway Configuration"),
                    selection: Binding(
                        get: { credentials.cloudflareConfigurationMode },
                        set: { credentials.setCloudflareConfigurationMode($0) }
                    )
                ) {
                    ForEach(CloudflareGatewayConfigurationMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Cloudflare gateway configuration"))
                .accessibilityIdentifier("settings.cloudflareMode")

                if credentials.cloudflareConfigurationMode == .custom {
                    TextField(
                        String(localized: "https://gateway.example/v1"),
                        text: $credentials.customCloudflareGatewayBaseURL
                    )
                    .focused(focusedField, equals: .cloudflareGatewayBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SettingsFieldFramePreferenceKey.self,
                                value: [.cloudflareGatewayBaseURL: geometry.frame(in: .named("settingsForm"))]
                            )
                        }
                    )
                    .accessibilityLabel(String(localized: "Custom Cloudflare gateway URL"))
                    .accessibilityIdentifier("settings.cloudflareCustomURL")
                    .onChange(of: credentials.customCloudflareGatewayBaseURL) { _, _ in
                        credentials.refreshCloudflareHealthStatus()
                    }

                    SecureField(
                        String(localized: "Cloudflare AIG token"),
                        text: $credentials.customCloudflareAIGToken
                    )
                    .focused(focusedField, equals: .cloudflareAIGToken)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SettingsFieldFramePreferenceKey.self,
                                value: [.cloudflareAIGToken: geometry.frame(in: .named("settingsForm"))]
                            )
                        }
                    )
                    .accessibilityLabel(String(localized: "Custom Cloudflare gateway token"))
                    .accessibilityIdentifier("settings.cloudflareCustomToken")
                    .onChange(of: credentials.customCloudflareAIGToken) { _, _ in
                        credentials.refreshCloudflareHealthStatus()
                    }

                    HStack {
                        Button(String(localized: "Clear Custom")) {
                            credentials.clearCustomCloudflareConfiguration()
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(String(localized: "Clear custom Cloudflare configuration"))
                        .accessibilityIdentifier("settings.clearCustomCloudflare")

                        Spacer()

                        Button(String(localized: "Save Custom")) {
                            credentials.saveCustomCloudflareConfiguration()
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(
                            credentials.customCloudflareGatewayBaseURL
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                                || credentials.customCloudflareAIGToken
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                        .accessibilityLabel(String(localized: "Save custom Cloudflare configuration"))
                        .accessibilityIdentifier("settings.saveCustomCloudflare")
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Connection Status"))
                        if let statusText {
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer()

                    if credentials.isCheckingCloudflareHealth {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(String(localized: "Checking connection"))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(statusAccessibilityLabel)
                .accessibilityIdentifier("settings.cloudflareStatus")

                Button(String(localized: "Check Connection")) {
                    Task { @MainActor in
                        await credentials.checkCloudflareHealth()
                    }
                }
                .buttonStyle(.glass)
                .disabled(credentials.isCheckingCloudflareHealth || isCustomConfigurationIncomplete)
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

    private var isCustomConfigurationIncomplete: Bool {
        guard credentials.cloudflareConfigurationMode == .custom else {
            return false
        }

        return credentials.customCloudflareGatewayBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            || credentials.customCloudflareAIGToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var statusText: String? {
        if credentials.cloudflareConfigurationMode == .custom,
           isCustomConfigurationIncomplete,
           credentials.cloudflareHealthStatus == .unknown {
            return nil
        }

        return switch credentials.cloudflareHealthStatus {
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

    private var statusAccessibilityLabel: String {
        guard let statusText else {
            return String(localized: "Cloudflare connection status")
        }

        return String(localized: "Cloudflare connection status") + ": \(statusText)"
    }
}
