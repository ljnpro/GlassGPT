import BackendContracts
import Foundation

public struct SyncProjectionBatch: Codable, Equatable, Sendable {
    public let nextCursor: SyncCursor?
    public let events: [RunEventDTO]

    public init(nextCursor: SyncCursor?, events: [RunEventDTO]) {
        self.nextCursor = nextCursor
        self.events = events
    }

    public init(envelope: SyncEnvelopeDTO) {
        self.init(
            nextCursor: envelope.nextCursor.map { SyncCursor(rawValue: $0) },
            events: envelope.events
        )
    }
}
