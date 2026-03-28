import ChatPresentation
import SwiftUI
import UIKit

enum SettingsFocusedField: Hashable {
    case apiKey
}

struct SettingsFieldFramePreferenceKey: PreferenceKey {
    static let defaultValue: [SettingsFocusedField: CGRect] = [:]

    static func reduce(value: inout [SettingsFocusedField: CGRect], nextValue: () -> [SettingsFocusedField: CGRect]) {
        for (field, frame) in nextValue() where !frame.isNull {
            value[field] = frame
        }
    }
}

@MainActor
private enum SettingsKeyboardDismisser {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

/// Main settings screen with account, backend credential, defaults, appearance, and cache management.
public struct SettingsView: View {
    @State private var account: SettingsAccountStore
    @State private var credentials: SettingsCredentialsStore
    @State private var defaults: SettingsDefaultsStore
    @State private var agentDefaults: AgentSettingsDefaultsStore
    @State private var cache: SettingsCacheStore
    @State private var fieldFrames: [SettingsFocusedField: CGRect] = [:]
    @FocusState private var focusedField: SettingsFocusedField?
    private let about: SettingsAboutInfo

    /// Creates a settings view backed by the given presenter.
    @MainActor
    public init(viewModel: SettingsPresenter) {
        _account = State(initialValue: viewModel.account)
        _credentials = State(initialValue: viewModel.credentials)
        _defaults = State(initialValue: viewModel.defaults)
        _agentDefaults = State(initialValue: viewModel.agentDefaults)
        _cache = State(initialValue: viewModel.cache)
        about = viewModel.about
    }

    /// The settings form content and confirmation alerts for the settings flow.
    public var body: some View {
        let imageCacheFooter = cacheFooterText(
            description: String(
                localized: "Generated images are cached automatically so old download links still open later. Maximum cache size"
            ),
            limit: cache.generatedImageCacheLimitString
        )
        let documentCacheFooter = cacheFooterText(
            description: String(
                localized: """
                Generated PDFs and other files are cached automatically so old download links still open \
                or share later. Maximum cache size
                """
            ),
            limit: cache.generatedDocumentCacheLimitString
        )

        NavigationStack {
            Form {
                SettingsAccountSection(viewModel: account)
                SettingsAPIConfigurationSection(
                    viewModel: credentials,
                    focusedField: $focusedField,
                    dismissKeyboard: dismissKeyboard
                )
                Section {
                    NavigationLink {
                        SettingsAgentDefaultsView(viewModel: agentDefaults)
                    } label: {
                        SettingsNavigationRowLabel(
                            title: String(localized: "Agent Defaults"),
                            systemImage: "person.3.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.agentDefaults")

                    NavigationLink {
                        SettingsCacheManagementView(
                            cache: cache,
                            imageCacheFooter: imageCacheFooter,
                            documentCacheFooter: documentCacheFooter
                        )
                    } label: {
                        SettingsNavigationRowLabel(
                            title: String(localized: "Cache"),
                            systemImage: "internaldrive"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.cache")

                    NavigationLink {
                        SettingsAboutView(
                            appVersionString: about.appVersionString,
                            platformString: about.platformString
                        )
                    } label: {
                        SettingsNavigationRowLabel(
                            title: String(localized: "About"),
                            systemImage: "info.circle"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.about")
                }
                SettingsChatDefaultsSection(viewModel: defaults)
                SettingsAppearanceSection(viewModel: defaults)
            }
            .listSectionSpacing(.compact)
            .coordinateSpace(name: "settingsForm")
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("settings.form")
            .onPreferenceChange(SettingsFieldFramePreferenceKey.self) { fieldFrames = $0 }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    guard let focusedField,
                          let fieldFrame = fieldFrames[focusedField],
                          !fieldFrame.contains(value.location)
                    else {
                        return
                    }

                    dismissKeyboard()
                },
                including: focusedField != nil ? .all : .none
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onChanged { _ in
                    guard focusedField != nil else { return }
                    dismissKeyboard()
                },
                including: focusedField != nil ? .all : .none
            )
            .navigationTitle(String(localized: "Settings"))
            .task(id: account.isSignedIn) {
                await credentials.refreshStatus()
            }
            .alert(String(localized: "API Key Saved"), isPresented: saveConfirmationBinding) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(localized: "Your OpenAI API key has been stored on the backend for this account."))
            }
        }
    }

    private func cacheFooterText(description: String, limit: String) -> String {
        "\(description): \(limit)."
    }

    private func dismissKeyboard() {
        focusedField = nil
        SettingsKeyboardDismisser.dismiss()
    }

    private var saveConfirmationBinding: Binding<Bool> {
        Binding(
            get: { credentials.saveConfirmation },
            set: { credentials.saveConfirmation = $0 }
        )
    }
}
