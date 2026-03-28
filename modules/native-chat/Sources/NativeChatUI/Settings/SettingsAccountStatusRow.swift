import BackendContracts
import SwiftUI

struct SettingsAccountStatusRow: View {
    let title: String
    let statusText: String
    let detailText: String?
    let state: HealthCheckStateDTO?
    let accessibilityIdentifier: String

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 8) {
                    SettingsStatusIndicator(state: state)
                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                }

                if let detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
