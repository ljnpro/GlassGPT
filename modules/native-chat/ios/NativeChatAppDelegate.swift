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
        
        // Create SwiftData container
        let container: ModelContainer
        do {
            let schema = Schema([Conversation.self, Message.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback: try without migration
            do {
                let schema = Schema([Conversation.self, Message.self])
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create SwiftData ModelContainer: \(error)")
            }
        }
        
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
}
