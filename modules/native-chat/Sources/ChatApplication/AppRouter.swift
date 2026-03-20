import ChatDomain
import Foundation
import Observation

/// Manages application navigation state and deep-link URL handling.
///
/// `AppRouter` owns the current navigation state and provides a central
/// point for programmatic navigation from coordinators, Shortcuts, Widgets,
/// and URL deep links.
@MainActor
@Observable
public final class AppRouter: Sendable {
    /// The URL scheme registered for deep linking.
    public static let urlScheme = "glassgpt"

    /// The currently active route.
    public var currentRoute: AppRoute = .chat

    /// An optional conversation identifier to navigate to when the chat tab is shown.
    public var pendingConversationID: UUID?

    /// An optional settings section to scroll to when the settings tab is shown.
    public var pendingSettingsSection: SettingsSection?

    /// Creates a new app router.
    public init() {}

    /// Navigate to a specific route.
    /// - Parameter route: The destination route.
    public func navigate(to route: AppRoute) {
        switch route {
        case .chat:
            pendingConversationID = nil
            currentRoute = .chat
        case let .chatConversation(id):
            pendingConversationID = id
            currentRoute = .chat
        case .history:
            currentRoute = .history
        case .settings:
            pendingSettingsSection = nil
            currentRoute = .settings
        case let .settingsSection(section):
            pendingSettingsSection = section
            currentRoute = .settings
        }
    }

    /// Attempts to handle a deep-link URL.
    /// - Parameter url: The URL to parse (e.g., `glassgpt://chat/UUID`).
    /// - Returns: `true` if the URL was recognized and handled.
    @discardableResult
    public func handleURL(_ url: URL) -> Bool {
        guard url.scheme == Self.urlScheme else {
            return false
        }

        let host = url.host() ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "chat":
            if let idString = pathComponents.first, let id = UUID(uuidString: idString) {
                navigate(to: .chatConversation(id))
            } else {
                navigate(to: .chat)
            }
            return true

        case "history":
            navigate(to: .history)
            return true

        case "settings":
            if let sectionString = pathComponents.first,
               let section = SettingsSection(rawValue: sectionString) {
                navigate(to: .settingsSection(section))
            } else {
                navigate(to: .settings)
            }
            return true

        default:
            return false
        }
    }

    /// Constructs a deep-link URL for the given route.
    /// - Parameter route: The route to encode.
    /// - Returns: A `glassgpt://` URL representing the route.
    public static func url(for route: AppRoute) -> URL? {
        switch route {
        case .chat:
            URL(string: "\(urlScheme)://chat")
        case let .chatConversation(id):
            URL(string: "\(urlScheme)://chat/\(id.uuidString)")
        case .history:
            URL(string: "\(urlScheme)://history")
        case .settings:
            URL(string: "\(urlScheme)://settings")
        case let .settingsSection(section):
            URL(string: "\(urlScheme)://settings/\(section.rawValue)")
        }
    }

    /// The tab index corresponding to the current route, for backward compatibility.
    public var selectedTabIndex: Int {
        get {
            switch currentRoute {
            case .chat, .chatConversation:
                0
            case .history:
                1
            case .settings, .settingsSection:
                2
            }
        }
        set {
            switch newValue {
            case 0: navigate(to: .chat)
            case 1: navigate(to: .history)
            case 2: navigate(to: .settings)
            default: break
            }
        }
    }
}
