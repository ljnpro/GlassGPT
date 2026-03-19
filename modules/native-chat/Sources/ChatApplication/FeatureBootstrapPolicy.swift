/// Controls which startup behaviors are enabled when the chat feature bootstraps.
public struct FeatureBootstrapPolicy: Equatable, Sendable {
    /// Whether to restore the most recent conversation on launch.
    public let restoreLastConversation: Bool
    /// Whether to register app lifecycle observers (e.g. background/foreground transitions).
    public let setupLifecycleObservers: Bool
    /// Whether to execute one-time launch tasks such as draft recovery.
    public let runLaunchTasks: Bool

    /// Creates a bootstrap policy with the given flags.
    public init(
        restoreLastConversation: Bool,
        setupLifecycleObservers: Bool,
        runLaunchTasks: Bool
    ) {
        self.restoreLastConversation = restoreLastConversation
        self.setupLifecycleObservers = setupLifecycleObservers
        self.runLaunchTasks = runLaunchTasks
    }

    /// Production policy with all startup behaviors enabled.
    public static let live = FeatureBootstrapPolicy(
        restoreLastConversation: true,
        setupLifecycleObservers: true,
        runLaunchTasks: true
    )

    /// Testing policy with all startup behaviors disabled for isolation.
    public static let testing = FeatureBootstrapPolicy(
        restoreLastConversation: false,
        setupLifecycleObservers: false,
        runLaunchTasks: false
    )
}
