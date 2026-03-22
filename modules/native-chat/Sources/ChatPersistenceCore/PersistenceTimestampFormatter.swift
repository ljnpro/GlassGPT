import Foundation

/// Shared store-path timestamp formatting used by persistence infrastructure.
package enum PersistenceTimestampFormatter {
    private static let formatter = Date.ISO8601FormatStyle(
        dateSeparator: .dash,
        dateTimeSeparator: .standard,
        timeSeparator: .colon,
        timeZoneSeparator: .omitted,
        includingFractionalSeconds: true,
        timeZone: .gmt
    )

    /// Returns a filesystem-safe ISO 8601 timestamp component for the given date.
    package static func storePathComponent(from date: Date) -> String {
        date.formatted(formatter).replacingOccurrences(of: ":", with: "-")
    }
}
