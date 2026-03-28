import SwiftUI

struct SettingsAdaptiveToggleRow: View {
    let title: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    @Binding var isOn: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    HStack {
                        Spacer(minLength: 0)
                        Toggle(isOn: $isOn) {
                            EmptyView()
                        }
                        .labelsHidden()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel)
                        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                        .accessibilityIdentifier(accessibilityIdentifier)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)

                    Toggle(isOn: $isOn) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
                    .accessibilityIdentifier(accessibilityIdentifier)
                }
            }
        }
    }
}
