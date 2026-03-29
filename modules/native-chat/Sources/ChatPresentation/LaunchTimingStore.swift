import Foundation
import Observation

/// Observable debug store for launch timing, memory usage, and diagnostic metrics.
@Observable
@MainActor
public final class LaunchTimingStore {
    /// Shared diagnostics store updated by launch instrumentation.
    public static let shared = LaunchTimingStore()

    /// Recorded launch duration in seconds.
    public var launchDuration: TimeInterval = 0
    /// Recorded time-to-interactive interval in seconds.
    public var timeToInteractive: TimeInterval = 0
    /// Last known available memory in bytes.
    public var availableMemoryBytes: UInt64 = 0
    /// Number of MetricKit payloads received during the session.
    public var metricPayloadCount = 0

    public var formattedLaunchDuration: String {
        String(format: "%.1f ms", launchDuration * 1000)
    }

    public var formattedTimeToInteractive: String {
        String(format: "%.1f ms", timeToInteractive * 1000)
    }

    public var formattedAvailableMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(availableMemoryBytes), countStyle: .memory)
    }
}
