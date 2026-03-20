import ChatApplication
import ChatDomain
import Foundation
import Testing

/// Tests for ``AppRouter`` URL handling and navigation state.
@MainActor
struct AppRouterTests {

    // MARK: - URL Handling

    @Test func handleChatURL() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://chat")!)
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func handleChatConversationURL() {
        let router = AppRouter()
        let id = UUID()
        let handled = router.handleURL(URL(string: "glassgpt://chat/\(id.uuidString)")!)
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == id)
    }

    @Test func handleHistoryURL() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://history")!)
        #expect(handled == true)
        #expect(router.currentRoute == .history)
    }

    @Test func handleSettingsURL() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://settings")!)
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    @Test func handleSettingsSectionURL() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://settings/apikey")!)
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == .apiKey)
    }

    @Test func handleUnknownHostReturnsNil() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://unknown")!)
        #expect(handled == false)
    }

    @Test func handleWrongSchemeReturnsNil() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "https://chat")!)
        #expect(handled == false)
    }

    @Test func handleInvalidConversationIDFallsBackToChat() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://chat/not-a-uuid")!)
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func handleInvalidSettingsSectionFallsBackToSettings() {
        let router = AppRouter()
        let handled = router.handleURL(URL(string: "glassgpt://settings/nonexistent")!)
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    // MARK: - URL Construction Round-Trip

    @Test func urlRoundTripForChat() {
        let url = AppRouter.url(for: .chat)
        #expect(url?.absoluteString == "glassgpt://chat")
    }

    @Test func urlRoundTripForConversation() {
        let id = UUID()
        let url = AppRouter.url(for: .chatConversation(id))
        #expect(url?.absoluteString == "glassgpt://chat/\(id.uuidString)")
    }

    @Test func urlRoundTripForHistory() {
        let url = AppRouter.url(for: .history)
        #expect(url?.absoluteString == "glassgpt://history")
    }

    @Test func urlRoundTripForSettings() {
        let url = AppRouter.url(for: .settings)
        #expect(url?.absoluteString == "glassgpt://settings")
    }

    @Test func urlRoundTripForSettingsSection() {
        let url = AppRouter.url(for: .settingsSection(.cloudflare))
        #expect(url?.absoluteString == "glassgpt://settings/cloudflare")
    }

    // MARK: - Navigation State

    @Test func navigateToChatClearsPendingConversation() {
        let router = AppRouter()
        router.navigate(to: .chatConversation(UUID()))
        router.navigate(to: .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func navigateToSettingsClearsPendingSection() {
        let router = AppRouter()
        router.navigate(to: .settingsSection(.apiKey))
        router.navigate(to: .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    // MARK: - Tab Index Compatibility

    @Test func tabIndexForChat() {
        let router = AppRouter()
        router.navigate(to: .chat)
        #expect(router.selectedTabIndex == 0)
    }

    @Test func tabIndexForHistory() {
        let router = AppRouter()
        router.navigate(to: .history)
        #expect(router.selectedTabIndex == 1)
    }

    @Test func tabIndexForSettings() {
        let router = AppRouter()
        router.navigate(to: .settings)
        #expect(router.selectedTabIndex == 2)
    }

    @Test func setTabIndexNavigates() {
        let router = AppRouter()
        router.selectedTabIndex = 1
        #expect(router.currentRoute == .history)
        router.selectedTabIndex = 0
        #expect(router.currentRoute == .chat)
    }

    // MARK: - SettingsSection

    @Test func allSettingsSectionsHaveRawValues() {
        #expect(SettingsSection.apiKey.rawValue == "apikey")
        #expect(SettingsSection.cloudflare.rawValue == "cloudflare")
        #expect(SettingsSection.appearance.rawValue == "appearance")
        #expect(SettingsSection.cache.rawValue == "cache")
        #expect(SettingsSection.about.rawValue == "about")
    }
}
