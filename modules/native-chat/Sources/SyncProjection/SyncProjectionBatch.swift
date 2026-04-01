import BackendContracts
import Foundation

/// A batch of run events with an optional pagination cursor for projection.
public struct SyncProjectionBatch: Codable, Equatable, Sendable {
    public let nextCursor: SyncCursor?
    public let events: [RunEventDTO]

    /// Creates a batch with the given cursor and events.
    public init(nextCursor: SyncCursor?, events: [RunEventDTO]) {
        self.nextCursor = nextCursor
        self.events = events
    }

    /// Creates a batch from a backend sync envelope DTO.
    public init(envelope: SyncEnvelopeDTO) {
        self.init(
            nextCursor: envelope.nextCursor.map { SyncCursor(rawValue: $0) },
            events: envelope.events
        )
    }
}
