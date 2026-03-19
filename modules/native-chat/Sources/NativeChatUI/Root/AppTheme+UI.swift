import ChatDomain
import SwiftUI

public extension AppTheme {
    /// Returns the `ColorScheme` for this theme, or `nil` to follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
