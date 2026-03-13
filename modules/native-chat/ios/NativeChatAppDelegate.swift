import ExpoModulesCore
import UIKit
import SwiftUI
import SwiftData

public class NativeChatAppDelegate: ExpoAppDelegateSubscriber {
    
    // MARK: - UIApplicationDelegate (forwarded by ExpoAppDelegate)
    
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Auto-configure relay server URL from Info.plist (injected by Expo from EXPO_PUBLIC_API_BASE_URL)
        if let relayURL = Bundle.main.infoDictionary?["RelayServerURL"] as? String,
           !relayURL.isEmpty {
            FeatureFlags.configurePlatformRelay(url: relayURL)
            #if DEBUG
            print("[Relay] Auto-configured relay server URL: \(relayURL)")
            #endif
        }
        
        // Schedule root replacement after React Native has set up the window
        DispatchQueue.main.async { [weak self] in
            self?.replaceRootViewController()
        }
        return true
    }
    
    // MARK: - Root View Controller Replacement
    
    private var retryCount = 0
    private let maxRetries = 20
    
    private func replaceRootViewController() {
        // Try to find the window from connected scenes
        var window: UIWindow?
        
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first {
            window = windowScene.windows.first(where: { $0.isKeyWindow })
                ?? windowScene.windows.first
        }
        
        guard let window = window else {
            // Retry with increasing delay if window not ready
            retryCount += 1
            if retryCount < maxRetries {
                let delay = min(Double(retryCount) * 0.1, 1.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.replaceRootViewController()
                }
            }
            return
        }
        
        // Create SwiftData container with proper migration handling
        let container = Self.createPersistentContainer()
        
        let rootView = NativeChatRootView()
            .modelContainer(container)
        
        let hostingController = UIHostingController(rootView: rootView)
        hostingController.view.backgroundColor = .systemBackground
        
        // Animate the transition for a smooth experience
        UIView.transition(
            with: window,
            duration: 0.3,
            options: [.transitionCrossDissolve],
            animations: {
                window.rootViewController = hostingController
            },
            completion: nil
        )
        window.makeKeyAndVisible()
    }

    // MARK: - SwiftData Container Creation

    /// Creates a persistent ModelContainer. If schema migration fails (e.g. new
    /// fields were added), the old store file is deleted and a fresh one is created.
    /// This ensures the app ALWAYS uses on-disk persistence, never in-memory.
    private static func createPersistentContainer() -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self])

        // First attempt: open existing store (lightweight migration handles
        // additive changes like new optional properties automatically).
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            #if DEBUG
            print("[SwiftData] Opened persistent store successfully")
            #endif
            return container
        } catch {
            #if DEBUG
            print("[SwiftData] Failed to open store: \(error.localizedDescription)")
            print("[SwiftData] Attempting to delete and recreate store…")
            #endif
        }

        // Second attempt: delete the corrupted/incompatible store and recreate.
        // This loses existing data but is far better than silently using in-memory
        // storage where ALL data is lost on every relaunch.
        deleteExistingStore()

        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            #if DEBUG
            print("[SwiftData] Created fresh persistent store after cleanup")
            #endif
            return container
        } catch {
            // This should essentially never happen on a clean slate.
            fatalError("[SwiftData] Cannot create ModelContainer even after cleanup: \(error)")
        }
    }

    /// Removes the default SwiftData SQLite files from the app's Application Support directory.
    private static func deleteExistingStore() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        // SwiftData stores its default database as "default.store" in Application Support
        let storeNames = ["default.store", "default.store-shm", "default.store-wal"]
        for name in storeNames {
            let url = appSupportURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    #if DEBUG
                    print("[SwiftData] Deleted \(name)")
                    #endif
                } catch {
                    #if DEBUG
                    print("[SwiftData] Failed to delete \(name): \(error.localizedDescription)")
                    #endif
                }
            }
        }
    }
}
