import ChatDomain
import ChatUIComponents
import SwiftUI

extension AgentSelectorSheet {
    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Agent Council"))
                    .font(.title3.weight(.semibold))

                Text(configurationSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(String(localized: "Current configuration") + ": \(configurationSummary)")
                    .accessibilityIdentifier("agentSelector.summary")
            }

            Spacer(minLength: 12)

            Button(action: onDone) {
                Text(String(localized: "Save"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .singleFrameGlassCapsuleControl(
                        tintOpacity: GlassStyleMetrics.CapsuleControl.tintOpacity,
                        borderWidth: GlassStyleMetrics.CapsuleControl.borderWidth,
                        darkBorderOpacity: GlassStyleMetrics.CapsuleControl.darkBorderOpacity,
                        lightBorderOpacity: GlassStyleMetrics.CapsuleControl.lightBorderOpacity
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel(String(localized: "Save Agent settings"))
            .accessibilityIdentifier("agentSelector.save")
        }
        .padding(.horizontal, 2)
    }

    var toggleGroup: some View {
        VStack(spacing: 0) {
            toggleRow(
                title: String(localized: "Background Mode"),
                subtitle: String(localized: "Keeps Agent runs recoverable across longer interruptions."),
                isOn: $backgroundModeEnabled,
                accessibilityIdentifier: "agentSelector.backgroundMode",
                rowAccessibilityIdentifier: "agentSelector.backgroundModeRow"
            )
            Divider().padding(.leading, metrics.rowHorizontalPadding)
            toggleRow(
                title: String(localized: "Flex Mode"),
                subtitle: String(localized: "Lower cost, but slower and less consistent response times."),
                isOn: $flexModeEnabled,
                accessibilityIdentifier: "agentSelector.flexMode",
                rowAccessibilityIdentifier: "agentSelector.flexModeRow"
            )
        }
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
    }

    func reasoningControl(
        title: String,
        effort: Binding<ReasoningEffort>,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(effort.wrappedValue.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: effort.wrappedValue)
                    .accessibilityLabel("\(title): \(effort.wrappedValue.displayName)")
                    .accessibilityIdentifier("\(accessibilityPrefix)Value")
            }
            .padding(.horizontal, 4)

            VStack(spacing: 4) {
                Slider(
                    value: sliderBinding(for: effort),
                    in: 0 ... Double(max(efforts.count - 1, 1)),
                    step: 1
                ) {
                    Text(title)
                } minimumValueLabel: {
                    Text(shortLabel(efforts.first ?? .none))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(shortLabel(efforts.last ?? .xhigh))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tint(.accentColor)
                .accessibilityLabel(title)
                .accessibilityValue(effort.wrappedValue.displayName)
                .accessibilityIdentifier("\(accessibilityPrefix)Slider")

                HStack {
                    ForEach(Array(efforts.enumerated()), id: \.offset) { _, candidate in
                        Text(shortLabel(candidate))
                            .font(.caption2)
                            .foregroundStyle(candidate == effort.wrappedValue ? .primary : .tertiary)
                            .fontWeight(candidate == effort.wrappedValue ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(metrics.rowHorizontalPadding)
        .singleSurfaceGlass(
            cornerRadius: metrics.cardCornerRadius,
            stableFillOpacity: GlassStyleMetrics.CompactSurface.stableFillOpacity,
            tintOpacity: GlassStyleMetrics.CompactSurface.tintOpacity,
            borderWidth: GlassStyleMetrics.CompactSurface.borderWidth,
            darkBorderOpacity: GlassStyleMetrics.CompactSurface.darkBorderOpacity,
            lightBorderOpacity: GlassStyleMetrics.CompactSurface.lightBorderOpacity
        )
    }

    func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityIdentifier: String,
        rowAccessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .padding(.horizontal, metrics.rowHorizontalPadding)
        .padding(.vertical, metrics.rowVerticalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rowAccessibilityIdentifier)
    }

    func sliderBinding(for effort: Binding<ReasoningEffort>) -> Binding<Double> {
        Binding<Double>(
            get: {
                Double(efforts.firstIndex(of: effort.wrappedValue) ?? 0)
            },
            set: { newValue in
                let index = Int(round(newValue))
                let clampedIndex = min(max(index, 0), efforts.count - 1)
                let newEffort = efforts[clampedIndex]
                guard newEffort != effort.wrappedValue else { return }
                effort.wrappedValue = newEffort
                HapticService.shared.selection(isEnabled: hapticsEnabled)
            }
        )
    }

    func shortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none:
            String(localized: "Off")
        case .low:
            String(localized: "Low")
        case .medium:
            String(localized: "Med")
        case .high:
            String(localized: "High")
        case .xhigh:
            String(localized: "Max")
        }
    }
}
