import Foundation

public struct SyncEnvelopeDTO: Codable, Equatable, Sendable {
    public let nextCursor: String?
    public let events: [RunEventDTO]

    public init(nextCursor: String?, events: [RunEventDTO]) {
        self.nextCursor = nextCursor
        self.events = events
    }
}
