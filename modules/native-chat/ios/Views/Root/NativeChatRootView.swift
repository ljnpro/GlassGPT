import SwiftUI

struct NativeChatRootView: View {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var body: some View {
        ContentView()
            .preferredColorScheme(selectedTheme.colorScheme)
    }
}
