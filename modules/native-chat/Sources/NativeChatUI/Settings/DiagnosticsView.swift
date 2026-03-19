#if DEBUG
import SwiftUI

/// Debug-only view displaying launch timing, memory usage, and diagnostic payload counts.
struct DiagnosticsView: View {
    var body: some View {
        List {
            Section(String(localized: "Launch Timing")) {
                LabeledContent(String(localized: "Launch Time"), value: LaunchTimingStore.shared.formattedLaunchDuration)
                LabeledContent(String(localized: "Time to Interactive"), value: LaunchTimingStore.shared.formattedTimeToInteractive)
            }

            Section(String(localized: "Memory")) {
                LabeledContent(String(localized: "Available"), value: LaunchTimingStore.shared.formattedAvailableMemory)
            }

            Section(String(localized: "MetricKit")) {
                LabeledContent(String(localized: "Payloads Received"), value: "\(LaunchTimingStore.shared.metricPayloadCount)")
            }
        }
        .navigationTitle(String(localized: "Diagnostics"))
    }
}

/// Simple observable store for launch timing and diagnostic metrics.
@MainActor
@Observable
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

    var formattedLaunchDuration: String {
        String(format: "%.1f ms", launchDuration * 1000)
    }

    var formattedTimeToInteractive: String {
        String(format: "%.1f ms", timeToInteractive * 1000)
    }

    var formattedAvailableMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(availableMemoryBytes), countStyle: .memory)
    }
}
#endif
