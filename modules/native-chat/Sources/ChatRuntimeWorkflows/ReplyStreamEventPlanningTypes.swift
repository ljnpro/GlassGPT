import ChatDomain
import Foundation

/// Semantic projection updates that composition maps onto concrete UI animation.
public enum ReplyStreamProjectionDirective: Equatable, Sendable {
    /// No visible projection update is required.
    case none
    /// Synchronize visible projection without animation.
    case sync
    /// Synchronize visible projection with a semantic animation hint.
    case animated(ReplyStreamProjectionAnimation)
}

/// Semantic animation hints for stream-driven projection changes.
public enum ReplyStreamProjectionAnimation: Equatable, Sendable {
    /// The model entered its thinking phase.
    case thinkingStarted
    /// The model exited its thinking phase.
    case thinkingFinished
    /// Text arrived immediately after a thinking phase.
    case textAfterThinking
    /// A tool call started.
    case toolStarted
    /// A tool call or annotation changed state.
    case activityUpdated
}

/// Persistence instructions associated with a stream event.
public enum ReplyStreamPersistenceDirective: Equatable, Sendable {
    /// No session persistence is needed.
    case none
    /// Persist when the session coordinator's save policy allows it.
    case saveIfNeeded
    /// Persist immediately.
    case saveNow
}

/// Persisted response metadata emitted by a stream event.
public struct ReplyResponseMetadataUpdate: Equatable, Sendable {
    /// The created response identifier.
    public let responseID: String
    /// Whether the originating request used background mode.
    public let usedBackgroundMode: Bool

    /// Creates a response metadata update.
    public init(responseID: String, usedBackgroundMode: Bool) {
        self.responseID = responseID
        self.usedBackgroundMode = usedBackgroundMode
    }
}

/// Runtime-owned outcome of applying a stream event.
public enum ReplyStreamEventOutcome: Equatable, Sendable {
    /// Streaming should continue normally.
    case continued
    /// Streaming completed successfully.
    case terminalCompleted
    /// Streaming reached an incomplete terminal state.
    case terminalIncomplete(String?)
    /// The connection was lost and recovery may be required.
    case connectionLost
    /// Streaming terminated with an error message.
    case terminalFailure(String)
}

/// Context needed to map a transport event into runtime-owned actions.
public struct ReplyStreamEventContext: Equatable, Sendable {
    /// The runtime route currently associated with the stream.
    public let route: OpenAITransportRoute
    /// Whether runtime state reported an active thinking phase before this event.
    public let wasThinking: Bool
    /// Whether runtime state has any active tool call before this event.
    public let hasActiveToolCalls: Bool
    /// Whether the originating request used background mode.
    public let usedBackgroundMode: Bool

    /// Creates a stream event context.
    public init(
        route: OpenAITransportRoute,
        wasThinking: Bool,
        hasActiveToolCalls: Bool = false,
        usedBackgroundMode: Bool
    ) {
        self.route = route
        self.wasThinking = wasThinking
        self.hasActiveToolCalls = hasActiveToolCalls
        self.usedBackgroundMode = usedBackgroundMode
    }
}

/// Runtime-owned plan for applying a transport stream event.
public struct ReplyStreamEventPlan: Equatable, Sendable {
    /// The transition to apply, if any.
    public let transition: ReplyRuntimeTransition?
    /// The projection update to perform after applying the transition.
    public let projection: ReplyStreamProjectionDirective
    /// The session persistence directive to execute.
    public let persistence: ReplyStreamPersistenceDirective
    /// Any response metadata that should be persisted onto the message.
    public let responseMetadataUpdate: ReplyResponseMetadataUpdate?
    /// The resulting stream outcome.
    public let outcome: ReplyStreamEventOutcome

    /// Creates a stream event plan.
    public init(
        transition: ReplyRuntimeTransition?,
        projection: ReplyStreamProjectionDirective,
        persistence: ReplyStreamPersistenceDirective,
        responseMetadataUpdate: ReplyResponseMetadataUpdate?,
        outcome: ReplyStreamEventOutcome
    ) {
        self.transition = transition
        self.projection = projection
        self.persistence = persistence
        self.responseMetadataUpdate = responseMetadataUpdate
        self.outcome = outcome
    }
}
