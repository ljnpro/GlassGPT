import Foundation

/// An opaque, lexicographically comparable cursor used for incremental sync pagination.
public struct SyncCursor: Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    /// Creates a cursor from the given raw string value.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: SyncCursor, rhs: SyncCursor) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
