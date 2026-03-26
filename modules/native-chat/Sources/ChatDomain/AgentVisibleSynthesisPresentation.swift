import Foundation

/// Persisted presentation state for the visible final-answer synthesis.
public struct AgentVisibleSynthesisPresentation: Codable, Equatable, Sendable {
    /// Short visible status text shown while the final answer is streaming.
    public var statusText: String
    /// Short visible summary describing the current synthesis progress.
    public var summaryText: String
    /// Recovery state for the visible synthesis stream.
    public var recoveryState: AgentRecoveryState
    /// Last update timestamp for the visible presentation state.
    public var updatedAt: Date

    /// Creates visible final-synthesis presentation state.
    public init(
        statusText: String = "",
        summaryText: String = "",
        recoveryState: AgentRecoveryState = .idle,
        updatedAt: Date = Date()
    ) {
        self.statusText = statusText
        self.summaryText = summaryText
        self.recoveryState = recoveryState
        self.updatedAt = updatedAt
    }
}
