import BackendAuth
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ChatUIComponents
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import NativeChatBackendComposition
@testable import NativeChatBackendCore
@testable import NativeChatUI

@Suite(.tags(.presentation))
@MainActor
struct NativeChatUIInteractionCoverageTests {
    @Test func `settings account section supports sign in connection checks and sign out`() async {
        let client = UICoverageBackendRequester()
        let sessionStore = BackendSessionStore()
        let account = SettingsAccountStore(
            sessionStore: sessionStore,
            client: client,
            signInAction: {
                sessionStore.replace(session: makeHarnessSession())
            },
            signOutAction: {
                sessionStore.clear()
            }
        )

        let signedOutController = hostViewController(
            Form {
                SettingsAccountSection(viewModel: account)
            }
        )
        _ = signedOutController.view

        await account.signIn()
        #expect(account.isSignedIn)

        client.connectionStatus = ConnectionCheckDTO(
            backend: .degraded,
            auth: .healthy,
            openaiCredential: .invalid,
            sse: .unavailable,
            checkedAt: .now,
            latencyMilliseconds: 28,
            errorSummary: "Realtime degraded"
        )
        let signedInController = hostViewController(
            Form {
                SettingsAccountSection(viewModel: account)
            }
        )
        _ = signedInController.view

        await account.checkConnection()
        #expect(account.connectionStatus?.backend == .degraded)
        #expect(account.syncStatusText == "Available with Degraded Realtime")

        await account.signOut()
        #expect(!account.isSignedIn)
        #expect(account.connectionStatus == nil)
    }

    @Test func `settings view renders account api key defaults and accessibility layouts`() async throws {
        let harness = try makeNativeChatHarness(signedIn: true)
        let presenter = harness.settingsPresenter
        harness.client.connectionStatus = ConnectionCheckDTO(
            backend: .healthy,
            auth: .healthy,
            openaiCredential: .healthy,
            sse: .healthy,
            checkedAt: .now,
            latencyMilliseconds: 11,
            errorSummary: nil
        )
        await presenter.account.checkConnection()
        presenter.credentials.apiKey = "sk-test-value"

        let standardController = hostViewController(SettingsView(viewModel: presenter), runLoopDelay: 0.4)
        _ = standardController.view

        await presenter.credentials.saveAPIKey()
        #expect(harness.client.storedAPIKeys == ["sk-test-value"])

        await presenter.credentials.refreshStatus()
        await presenter.credentials.deleteAPIKey()
        #expect(harness.client.deleteOpenAIKeyCallCount == 1)

        let compactDefaults = SettingsDefaultsStore(settingsStore: SettingsStore())
        compactDefaults.defaultProModeEnabled = true
        compactDefaults.defaultFlexModeEnabled = true
        compactDefaults.hapticEnabled = false
        let accessibilityController = hostViewController(
            Form {
                SettingsChatDefaultsSection(viewModel: compactDefaults)
                SettingsAppearanceSection(viewModel: compactDefaults)
            }
            .environment(\.dynamicTypeSize, .accessibility3)
        )
        _ = accessibilityController.view
        #expect(compactDefaults.defaultProModeEnabled)
        #expect(compactDefaults.defaultFlexModeEnabled)
        #expect(!compactDefaults.hapticEnabled)

        try? FileManager.default.removeItem(at: harness.cacheRoot)
    }

    @Test func `selector sheets support compact regular and interactive control changes`() {
        var backendProEnabled = true
        var backendFlexEnabled = false
        var backendReasoningEffort = ReasoningEffort.high
        hostViewController(
            BackendChatSelectorSheet(
                proModeEnabled: Binding(get: { backendProEnabled }, set: { backendProEnabled = $0 }),
                flexModeEnabled: Binding(get: { backendFlexEnabled }, set: { backendFlexEnabled = $0 }),
                reasoningEffort: Binding(get: { backendReasoningEffort }, set: { backendReasoningEffort = $0 }),
                onDone: {}
            )
        )
        backendProEnabled = false
        backendFlexEnabled = true
        backendReasoningEffort = .low
        hostViewController(
            BackendChatSelectorSheet(
                proModeEnabled: Binding(get: { backendProEnabled }, set: { backendProEnabled = $0 }),
                flexModeEnabled: Binding(get: { backendFlexEnabled }, set: { backendFlexEnabled = $0 }),
                reasoningEffort: Binding(get: { backendReasoningEffort }, set: { backendReasoningEffort = $0 }),
                onDone: {}
            )
            .environment(\.horizontalSizeClass, .regular)
        )

        var backendAgentFlexEnabled = false
        var backendLeaderEffort = ReasoningEffort.high
        var backendWorkerEffort = ReasoningEffort.low
        hostViewController(
            BackendAgentSelectorSheet(
                flexModeEnabled: Binding(get: { backendAgentFlexEnabled }, set: { backendAgentFlexEnabled = $0 }),
                leaderReasoningEffort: Binding(get: { backendLeaderEffort }, set: { backendLeaderEffort = $0 }),
                workerReasoningEffort: Binding(get: { backendWorkerEffort }, set: { backendWorkerEffort = $0 }),
                onDone: {}
            )
        )
        backendAgentFlexEnabled = true
        backendLeaderEffort = .medium
        backendWorkerEffort = .xhigh
        hostViewController(
            BackendAgentSelectorSheet(
                flexModeEnabled: Binding(get: { backendAgentFlexEnabled }, set: { backendAgentFlexEnabled = $0 }),
                leaderReasoningEffort: Binding(get: { backendLeaderEffort }, set: { backendLeaderEffort = $0 }),
                workerReasoningEffort: Binding(get: { backendWorkerEffort }, set: { backendWorkerEffort = $0 }),
                onDone: {}
            )
            .environment(\.horizontalSizeClass, .regular)
        )
    }
}
