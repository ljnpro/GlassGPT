public struct FeatureBootstrapPolicy: Equatable, Sendable {
    public let restoreLastConversation: Bool
    public let setupLifecycleObservers: Bool
    public let runLaunchTasks: Bool

    public init(
        restoreLastConversation: Bool,
        setupLifecycleObservers: Bool,
        runLaunchTasks: Bool
    ) {
        self.restoreLastConversation = restoreLastConversation
        self.setupLifecycleObservers = setupLifecycleObservers
        self.runLaunchTasks = runLaunchTasks
    }

    public static let live = FeatureBootstrapPolicy(
        restoreLastConversation: true,
        setupLifecycleObservers: true,
        runLaunchTasks: true
    )

    public static let testing = FeatureBootstrapPolicy(
        restoreLastConversation: false,
        setupLifecycleObservers: false,
        runLaunchTasks: false
    )
}
