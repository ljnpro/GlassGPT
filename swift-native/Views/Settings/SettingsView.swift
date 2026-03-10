import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - API Configuration
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
                            Task { await viewModel.validateAPIKey() }
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

                // MARK: - Chat Defaults
                Section("Chat Defaults") {
                    Picker("Default Model", selection: $viewModel.defaultModel) {
                        ForEach(ModelType.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }

                    Picker("Reasoning Effort", selection: $viewModel.defaultEffort) {
                        ForEach(ReasoningEffort.allCases) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                }

                // MARK: - Appearance
                Section("Appearance") {
                    Picker("Theme", selection: $viewModel.appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Haptic Feedback", isOn: $viewModel.hapticEnabled)
                }

                // MARK: - About
                Section("About") {
                    LabeledContent("Version", value: "2.0.0")
                    LabeledContent("Platform", value: "iOS 26 · Swift 6")
                    LabeledContent("Engine", value: "SwiftUI · Liquid Glass")

                    Link(destination: URL(string: "https://ljnpro.github.io/liquid-glass-chat-support/")!) {
                        HStack {
                            Text("Support Website")
                            Spacer()
                            Image(systemName: "safari")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("API Key Saved", isPresented: $viewModel.saveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your OpenAI API key has been saved to Keychain.")
            }
        }
    }
}
