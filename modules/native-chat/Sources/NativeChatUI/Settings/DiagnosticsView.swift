#if DEBUG
import SwiftUI

/// Debug-only view displaying launch timing, memory usage, and diagnostic payload counts.
struct DiagnosticsView: View {
    var body: some View {
        List {
            Section("Launch Timing") {
                LabeledContent("Launch Time", value: LaunchTimingStore.shared.formattedLaunchDuration)
                LabeledContent("Time to Interactive", value: LaunchTimingStore.shared.formattedTimeToInteractive)
            }

            Section("Memory") {
                LabeledContent("Available", value: LaunchTimingStore.shared.formattedAvailableMemory)
            }

            Section("MetricKit") {
                LabeledContent("Payloads Received", value: "\(LaunchTimingStore.shared.metricPayloadCount)")
            }
        }
        .navigationTitle("Diagnostics")
    }
}

/// Simple observable store for launch timing and diagnostic metrics.
@MainActor
@Observable
public final class LaunchTimingStore {
    public static let shared = LaunchTimingStore()

    public var launchDuration: TimeInterval = 0
    public var timeToInteractive: TimeInterval = 0
    public var availableMemoryBytes: UInt64 = 0
    public var metricPayloadCount: Int = 0

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
