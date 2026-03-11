import SwiftUI

// MARK: - Model Badge (Toolbar)

struct ModelBadge: View {
    let model: ModelType
    let effort: ReasoningEffort
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))

                if effort != .none {
                    Text("·")
                        .font(.caption)
                    Text(effort.displayName)
                        .font(.caption)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Selector Sheet

struct ModelSelectorSheet: View {
    @Binding var selectedModel: ModelType
    @Binding var reasoningEffort: ReasoningEffort
    @Environment(\.dismiss) private var dismiss

    /// Available efforts for the current model.
    private var efforts: [ReasoningEffort] {
        selectedModel.availableEfforts
    }

    /// Current effort as a slider index value.
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
            // Header bar
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

            // Content
            VStack(spacing: 20) {
                // Model selection — two equal-width cards
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    HStack(spacing: 10) {
                        ForEach(ModelType.allCases) { model in
                            modelChip(model)
                        }
                    }
                }

                // Reasoning Effort — Native iOS 26 Slider (Liquid Glass)
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

                    // Native Slider — on iOS 26 this automatically renders
                    // with Liquid Glass thumb and track styling.
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

                        // Tick labels below the slider
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
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Model Chip

    private func modelChip(_ model: ModelType) -> some View {
        let isSelected = model == selectedModel

        return Button {
            let previousModel = selectedModel
            selectedModel = model
            if !model.availableEfforts.contains(reasoningEffort) {
                reasoningEffort = model.defaultEffort
            }
            if model != previousModel {
                HapticService.shared.selection()
            }
        } label: {
            VStack(spacing: 4) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))

                Text(modelDescription(for: model))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    // MARK: - Descriptions

    private func modelDescription(for model: ModelType) -> String {
        switch model {
        case .gpt5_4: return "Fast and capable"
        case .gpt5_4_pro: return "Complex reasoning"
        }
    }

    /// Short labels for the slider ticks.
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
