#if DEBUG
import ChatPresentation
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

#endif
