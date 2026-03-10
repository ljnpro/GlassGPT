import SwiftUI
import SwiftData

@main
struct LiquidGlassChatApp: App {
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Conversation.self,
            Message.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }()

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(selectedTheme.colorScheme)
        }
        .modelContainer(sharedModelContainer)
    }
}
