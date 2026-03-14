import SwiftUI

// MARK: - Model Badge (Toolbar)

struct ModelBadge: View {
    let model: ModelType
    let effort: ReasoningEffort
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(badgeText)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .capsule)
    }

    private var badgeText: String {
        if effort == .none {
            return model.displayName
        }
        return "\(model.displayName) \(effort.displayName)"
    }
}

// MARK: - Model Selector Sheet

struct ModelSelectorSheet: View {
    @Binding var proModeEnabled: Bool
    @Binding var backgroundModeEnabled: Bool
    @Binding var flexModeEnabled: Bool
    @Binding var reasoningEffort: ReasoningEffort
    @Environment(\.dismiss) private var dismiss

    private var selectedModel: ModelType {
        proModeEnabled ? .gpt5_4_pro : .gpt5_4
    }

    private var efforts: [ReasoningEffort] {
        selectedModel.availableEfforts
    }

    private var sliderBinding: Binding<Double> {
        Binding<Double>(
            get: {
                Double(efforts.firstIndex(of: reasoningEffort) ?? 0)
            },
            set: { newValue in
                let index = Int(round(newValue))
                let clampedIndex = min(max(index, 0), efforts.count - 1)
                let newEffort = efforts[clampedIndex]
                if newEffort != reasoningEffort {
                    reasoningEffort = newEffort
                    HapticService.shared.selection()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Model")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toggleCard(
                        title: "Pro Mode",
                        subtitle: "Switches between GPT-5.4 and GPT-5.4 Pro.",
                        isOn: $proModeEnabled
                    )

                    toggleCard(
                        title: "Background Mode",
                        subtitle: "Slower initial response, but better resume for long-running generations.",
                        isOn: $backgroundModeEnabled
                    )

                    toggleCard(
                        title: "Flex Mode",
                        subtitle: "Lower cost, but slower and less consistent response times.",
                        isOn: $flexModeEnabled
                    )

                    reasoningControl
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }

    private var reasoningControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reasoning")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(reasoningEffort.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.15), value: reasoningEffort)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 4) {
                Slider(
                    value: sliderBinding,
                    in: 0...Double(max(efforts.count - 1, 1)),
                    step: 1
                ) {
                    Text("Reasoning Effort")
                } minimumValueLabel: {
                    Text(effortShortLabel(efforts.first ?? .none))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(effortShortLabel(efforts.last ?? .xhigh))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .tint(.accentColor)

                HStack {
                    ForEach(Array(efforts.enumerated()), id: \.offset) { _, effort in
                        Text(effortShortLabel(effort))
                            .font(.caption2)
                            .foregroundStyle(effort == reasoningEffort ? .primary : .tertiary)
                            .fontWeight(effort == reasoningEffort ? .semibold : .regular)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func toggleCard(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(title, isOn: isOn)
                .font(.subheadline.weight(.medium))
                .onChange(of: isOn.wrappedValue) { _, _ in
                    HapticService.shared.selection()
                }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func effortShortLabel(_ effort: ReasoningEffort) -> String {
        switch effort {
        case .none: return "Off"
        case .low: return "Low"
        case .medium: return "Med"
        case .high: return "High"
        case .xhigh: return "Max"
        }
    }
}
