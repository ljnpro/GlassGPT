import Foundation

/// Shared store-path timestamp formatting used by persistence infrastructure.
package enum PersistenceTimestampFormatter {
    /// Returns a filesystem-safe ISO 8601 timestamp component for the given date.
    package static func storePathComponent(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }
}
