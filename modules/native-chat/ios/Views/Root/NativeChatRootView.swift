import SwiftUI

public struct NativeChatRootView: View {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue

    public init() {}

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    public var body: some View {
        ContentView()
            .preferredColorScheme(selectedTheme.colorScheme)
    }
}
