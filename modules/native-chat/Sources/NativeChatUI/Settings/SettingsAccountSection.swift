import ChatPresentation
import ChatUIComponents
import SwiftUI

struct SettingsAccountSection: View {
    @Bindable var viewModel: SettingsAccountStore

    var body: some View {
        Section {
            LabeledContent(String(localized: "Apple ID")) {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(viewModel.displayName)
                        .font(.headline.weight(.semibold))
                    Text(viewModel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.trailing)
            }

            SettingsAccountStatusRow(
                title: String(localized: "Session"),
                statusText: viewModel.sessionStatusText,
                detailText: nil,
                state: viewModel.sessionStatusState,
                accessibilityIdentifier: "settings.account.session"
            )

            SettingsAccountStatusRow(
                title: String(localized: "Sync"),
                statusText: viewModel.syncStatusText,
                detailText: viewModel.syncStatusDetailText,
                state: viewModel.syncStatusState,
                accessibilityIdentifier: "settings.account.sync"
            )

            if let status = viewModel.connectionStatus {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "Latest Connection Check"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ], spacing: 10) {
                        SettingsHealthChip(title: String(localized: "Backend"), state: status.backend)
                        SettingsHealthChip(title: String(localized: "Auth"), state: status.auth)
                        SettingsHealthChip(title: String(localized: "OpenAI"), state: status.openaiCredential)
                        SettingsHealthChip(title: String(localized: "Realtime"), state: status.sse)
                    }

                    if let latency = status.latencyMilliseconds {
                        Text(String(localized: "Latency: \(latency) ms"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.account.latency")
                    }

                    if let errorSummary = status.errorSummary, !errorSummary.isEmpty {
                        Text(errorSummary)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settings.account.connection")
                    }

                    if let compatibilityMessage = viewModel.compatibilityMessage, !compatibilityMessage.isEmpty {
                        Text(compatibilityMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("settings.account.compatibility")
                    }
                }
                .padding(.vertical, 4)
            }

            if let lastErrorMessage = viewModel.lastErrorMessage, !lastErrorMessage.isEmpty {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.account.error")
            }

            HStack {
                if viewModel.isSignedIn {
                    Button(String(localized: "Check Connection")) {
                        Task { @MainActor in
                            await viewModel.checkConnection()
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle(kind: .standard))
                    .disabled(viewModel.isCheckingConnection)
                    .accessibilityIdentifier("settings.account.checkConnection")

                    Spacer()

                    Button(String(localized: "Sign Out"), role: .destructive) {
                        Task { @MainActor in
                            await viewModel.signOut()
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle(kind: .destructive))
                    .disabled(viewModel.isSigningOut)
                    .accessibilityIdentifier("settings.account.signOut")
                } else {
                    SettingsCallToActionButton(
                        title: String(localized: "Sign In with Apple"),
                        accessibilityIdentifier: "settings.account.signIn"
                    ) {
                        Task { @MainActor in
                            await viewModel.signIn()
                        }
                    }
                    .disabled(viewModel.isAuthenticating)
                }
            }
        } header: {
            SettingsSectionHeaderText(text: String(localized: "Account & Sync"))
        } footer: {
            SettingsSectionFooterText(
                text: String(localized: "All chat and agent execution now runs through your backend account and syncs back to this device.")
            )
        }
    }
}
