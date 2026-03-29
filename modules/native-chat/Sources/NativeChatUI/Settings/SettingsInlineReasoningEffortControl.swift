import ChatDomain
import ChatUIComponents
import SwiftUI

struct SettingsInlineReasoningEffortControl: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var selectedEffort: ReasoningEffort
    let availableEfforts: [ReasoningEffort]
    @Environment(\.hapticsEnabled) private var hapticsEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Menu {
            ForEach(availableEfforts) { effort in
                Button {
                    guard effort != selectedEffort else { return }
                    selectedEffort = effort
                    HapticService.shared.selection(isEnabled: hapticsEnabled)
                } label: {
                    if effort == selectedEffort {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text(visibleEffortLabel(effort))
                        }
                    } else {
                        Text(visibleEffortLabel(effort))
                    }
                }
                .accessibilityIdentifier("\(accessibilityIdentifier).\(effort.rawValue)")
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.headline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            Spacer(minLength: 0)
                            selectionLabel
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Text(title)
                            .font(.headline.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        selectionLabel
                    }
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(visibleEffortLabel(selectedEffort))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var selectionLabel: some View {
        HStack(spacing: 6) {
            Text(visibleEffortLabel(selectedEffort))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func visibleEffortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            String(localized: "None")
        case .low:
            String(localized: "Low")
        case .medium:
            String(localized: "Medium")
        case .high:
            String(localized: "High")
        case .xhigh:
            String(localized: "XHigh")
        }
    }
}
