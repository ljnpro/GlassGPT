import Foundation

/// A batch of run events returned by the incremental sync endpoint.
public struct SyncEnvelopeDTO: Codable, Equatable, Sendable {
    public let nextCursor: String?
    public let events: [RunEventDTO]

    /// Creates a sync envelope with the given pagination cursor and events.
    public init(nextCursor: String?, events: [RunEventDTO]) {
        self.nextCursor = nextCursor
        self.events = events
    }
}
