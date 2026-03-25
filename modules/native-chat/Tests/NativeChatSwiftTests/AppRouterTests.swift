import ChatApplication
import ChatDomain
import Foundation
import Testing

/// Tests for ``AppRouter`` URL handling and navigation state.
@MainActor
struct AppRouterTests {
    // MARK: - URL Handling

    @Test func `handle chat URL`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://chat")))
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func `handle chat conversation URL`() throws {
        let router = AppRouter()
        let id = UUID()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://chat/\(id.uuidString)")))
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == id)
    }

    @Test func `handle history URL`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://history")))
        #expect(handled == true)
        #expect(router.currentRoute == .history)
    }

    @Test func `handle agent URL`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://agent")))
        #expect(handled == true)
        #expect(router.currentRoute == .agent)
        #expect(router.pendingAgentConversationID == nil)
    }

    @Test func `handle agent conversation URL`() throws {
        let router = AppRouter()
        let id = UUID()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://agent/\(id.uuidString)")))
        #expect(handled == true)
        #expect(router.currentRoute == .agent)
        #expect(router.pendingAgentConversationID == id)
    }

    @Test func `handle settings URL`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://settings")))
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    @Test func `handle settings section URL`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://settings/apikey")))
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == .apiKey)
    }

    @Test func `handle unknown host returns nil`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://unknown")))
        #expect(handled == false)
    }

    @Test func `handle wrong scheme returns nil`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "https://chat")))
        #expect(handled == false)
    }

    @Test func `handle invalid conversation ID falls back to chat`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://chat/not-a-uuid")))
        #expect(handled == true)
        #expect(router.currentRoute == .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func `handle invalid settings section falls back to settings`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://settings/nonexistent")))
        #expect(handled == true)
        #expect(router.currentRoute == .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    @Test func `handle invalid agent conversation ID falls back to agent`() throws {
        let router = AppRouter()
        let handled = try router.handleURL(#require(URL(string: "glassgpt://agent/not-a-uuid")))
        #expect(handled == true)
        #expect(router.currentRoute == .agent)
        #expect(router.pendingAgentConversationID == nil)
    }

    // MARK: - URL Construction Round-Trip

    @Test func `url round trip for chat`() {
        let url = AppRouter.url(for: .chat)
        #expect(url?.absoluteString == "glassgpt://chat")
    }

    @Test func `url round trip for conversation`() {
        let id = UUID()
        let url = AppRouter.url(for: .chatConversation(id))
        #expect(url?.absoluteString == "glassgpt://chat/\(id.uuidString)")
    }

    @Test func `url round trip for history`() {
        let url = AppRouter.url(for: .history)
        #expect(url?.absoluteString == "glassgpt://history")
    }

    @Test func `url round trip for agent`() {
        let url = AppRouter.url(for: .agent)
        #expect(url?.absoluteString == "glassgpt://agent")
    }

    @Test func `url round trip for agent conversation`() {
        let id = UUID()
        let url = AppRouter.url(for: .agentConversation(id))
        #expect(url?.absoluteString == "glassgpt://agent/\(id.uuidString)")
    }

    @Test func `url round trip for settings`() {
        let url = AppRouter.url(for: .settings)
        #expect(url?.absoluteString == "glassgpt://settings")
    }

    @Test func `url round trip for settings section`() {
        let url = AppRouter.url(for: .settingsSection(.cloudflare))
        #expect(url?.absoluteString == "glassgpt://settings/cloudflare")
    }

    // MARK: - Navigation State

    @Test func `navigate to chat clears pending conversation`() {
        let router = AppRouter()
        router.navigate(to: .chatConversation(UUID()))
        router.navigate(to: .chat)
        #expect(router.pendingConversationID == nil)
    }

    @Test func `navigate to settings clears pending section`() {
        let router = AppRouter()
        router.navigate(to: .settingsSection(.apiKey))
        router.navigate(to: .settings)
        #expect(router.pendingSettingsSection == nil)
    }

    @Test func `navigate to agent clears pending agent conversation`() {
        let router = AppRouter()
        router.navigate(to: .agentConversation(UUID()))
        router.navigate(to: .agent)
        #expect(router.pendingAgentConversationID == nil)
    }

    // MARK: - Tab Index Compatibility

    @Test func `tab index for chat`() {
        let router = AppRouter()
        router.navigate(to: .chat)
        #expect(router.selectedTabIndex == 0)
    }

    @Test func `tab index for history`() {
        let router = AppRouter()
        router.navigate(to: .history)
        #expect(router.selectedTabIndex == 2)
    }

    @Test func `tab index for agent`() {
        let router = AppRouter()
        router.navigate(to: .agent)
        #expect(router.selectedTabIndex == 1)
    }

    @Test func `tab index for settings`() {
        let router = AppRouter()
        router.navigate(to: .settings)
        #expect(router.selectedTabIndex == 3)
    }

    @Test func `set tab index navigates`() {
        let router = AppRouter()
        router.selectedTabIndex = 1
        #expect(router.currentRoute == .agent)
        router.selectedTabIndex = 2
        #expect(router.currentRoute == .history)
        router.selectedTabIndex = 0
        #expect(router.currentRoute == .chat)
    }

    // MARK: - SettingsSection

    @Test func `all settings sections have raw values`() {
        #expect(SettingsSection.apiKey.rawValue == "apikey")
        #expect(SettingsSection.cloudflare.rawValue == "cloudflare")
        #expect(SettingsSection.appearance.rawValue == "appearance")
        #expect(SettingsSection.cache.rawValue == "cache")
        #expect(SettingsSection.about.rawValue == "about")
    }
}
