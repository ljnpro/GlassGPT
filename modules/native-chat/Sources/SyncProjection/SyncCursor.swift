import Foundation

public struct SyncCursor: Codable, Equatable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: SyncCursor, rhs: SyncCursor) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
