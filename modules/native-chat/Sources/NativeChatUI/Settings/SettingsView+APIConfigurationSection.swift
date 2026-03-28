import ChatPresentation
import ChatUIComponents
import SwiftUI

struct SettingsAPIConfigurationSection: View {
    @Bindable var viewModel: SettingsCredentialsStore
    let focusedField: FocusState<SettingsFocusedField?>.Binding
    let dismissKeyboard: @MainActor () -> Void

    var body: some View {
        Section {
            SecureField(String(localized: "sk-proj-..."), text: $viewModel.apiKey)
                .focused(focusedField, equals: .apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SettingsFieldFramePreferenceKey.self,
                            value: [.apiKey: geometry.frame(in: .named("settingsForm"))]
                        )
                    }
                )
                .accessibilityLabel(String(localized: "API key input"))
                .accessibilityIdentifier("settings.apiKey")

            Text(viewModel.statusLabel)
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.84))
                .accessibilityIdentifier("settings.apiKeyStatus")

            if let lastErrorMessage = viewModel.lastErrorMessage, !lastErrorMessage.isEmpty {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.apiKeyError")
            }

            if viewModel.isSignedIn {
                HStack {
                    Button(String(localized: "Refresh Status")) {
                        dismissKeyboard()
                        Task { @MainActor in
                            await viewModel.refreshStatus()
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle(kind: .standard))
                    .disabled(viewModel.isRefreshingStatus)
                    .accessibilityIdentifier("settings.refreshAPIKeyStatus")

                    Spacer()

                    Button(String(localized: "Revoke"), role: .destructive) {
                        dismissKeyboard()
                        Task { @MainActor in
                            await viewModel.deleteAPIKey()
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle(kind: .destructive))
                    .disabled(viewModel.isDeleting)
                    .accessibilityIdentifier("settings.clearAPIKey")

                    Button(String(localized: "Save")) {
                        dismissKeyboard()
                        Task { @MainActor in
                            await viewModel.saveAPIKey()
                        }
                    }
                    .buttonStyle(SettingsActionButtonStyle(kind: .prominent))
                    .disabled(viewModel.apiKey.isEmpty || viewModel.isSaving)
                    .accessibilityIdentifier("settings.saveAPIKey")
                }
            } else {
                Text(
                    String(
                        localized: """
                        Sign in with Apple first. Your key is stored encrypted on the backend and billed \
                        to your own OpenAI account.
                        """
                    )
                )
                .font(.body)
                .foregroundStyle(Color.primary.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeaderText(text: String(localized: "OpenAI API Key"))
        }
    }
}
