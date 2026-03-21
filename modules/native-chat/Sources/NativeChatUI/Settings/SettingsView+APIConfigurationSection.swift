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
                    dismissKeyboard()
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
                    dismissKeyboard()
                    viewModel.clearAPIKey()
                }
                .buttonStyle(.glass)
                .tint(.red)
                .accessibilityLabel(String(localized: "Clear API key"))
                .accessibilityIdentifier("settings.clearAPIKey")

                Button(String(localized: "Save")) {
                    dismissKeyboard()
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
