import SwiftUI
import ChatDomain

extension AppTheme {
    /// Returns the `ColorScheme` for this theme, or `nil` to follow the system setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
