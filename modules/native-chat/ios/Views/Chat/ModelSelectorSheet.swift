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
                    .font(.caption.weight(.semibold))

                if effort != .none {
                    Text("·")
                    Text(effort.displayName)
                        .font(.caption2)
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Model Selector Sheet

struct ModelSelectorSheet: View {
    @Binding var selectedModel: ModelType
    @Binding var reasoningEffort: ReasoningEffort
    @Environment(\.dismiss) private var dismiss

    /// Map slider value to the available efforts for the current model.
    private var efforts: [ReasoningEffort] {
        selectedModel.availableEfforts
    }

    /// Slider value derived from the current effort index.
    private var sliderValue: Double {
        guard let idx = efforts.firstIndex(of: reasoningEffort) else {
            return Double(efforts.count / 2)
        }
        return Double(idx)
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

                // Reasoning Effort — Liquid Glass slider
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

                    // Stepped slider with tick marks
                    EffortSlider(
                        efforts: efforts,
                        selected: $reasoningEffort
                    )
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
}

// MARK: - Effort Slider

/// A custom stepped slider with Liquid Glass styling and labeled tick marks.
struct EffortSlider: View {
    let efforts: [ReasoningEffort]
    @Binding var selected: ReasoningEffort

    @State private var isDragging = false

    private var stepCount: Int { efforts.count - 1 }

    private var currentIndex: Int {
        efforts.firstIndex(of: selected) ?? 0
    }

    var body: some View {
        VStack(spacing: 6) {
            // Slider track with glass thumb
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let thumbSize: CGFloat = 28

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .frame(height: 6)
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }

                    // Active track fill
                    let fillWidth = stepCount > 0
                        ? CGFloat(currentIndex) / CGFloat(stepCount) * (trackWidth - thumbSize) + thumbSize / 2
                        : thumbSize / 2

                    Capsule()
                        .fill(Color.accentColor.opacity(0.5))
                        .frame(width: fillWidth, height: 6)

                    // Tick marks
                    ForEach(0...stepCount, id: \.self) { i in
                        let xPos = stepCount > 0
                            ? CGFloat(i) / CGFloat(stepCount) * (trackWidth - thumbSize) + thumbSize / 2
                            : trackWidth / 2

                        Circle()
                            .fill(i <= currentIndex ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: 6, height: 6)
                            .position(x: xPos, y: geo.size.height / 2)
                    }

                    // Glass thumb
                    let thumbX = stepCount > 0
                        ? CGFloat(currentIndex) / CGFloat(stepCount) * (trackWidth - thumbSize)
                        : (trackWidth - thumbSize) / 2

                    Circle()
                        .fill(.ultraThickMaterial)
                        .frame(width: thumbSize, height: thumbSize)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .scaleEffect(isDragging ? 1.15 : 1.0)
                        .offset(x: thumbX)
                        .animation(.spring(duration: 0.25), value: currentIndex)
                        .animation(.spring(duration: 0.2), value: isDragging)
                }
                .frame(height: thumbSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let fraction = (value.location.x - thumbSize / 2) / (trackWidth - thumbSize)
                            let clamped = min(max(fraction, 0), 1)
                            let newIndex = Int(round(clamped * Double(stepCount)))
                            let newEffort = efforts[newIndex]
                            if newEffort != selected {
                                selected = newEffort
                                HapticService.shared.selection()
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 28)

            // Labels below the slider
            HStack {
                ForEach(Array(efforts.enumerated()), id: \.offset) { index, effort in
                    Text(effortShortLabel(effort))
                        .font(.caption2)
                        .foregroundStyle(effort == selected ? .primary : .secondary)
                        .fontWeight(effort == selected ? .semibold : .regular)
                        .frame(maxWidth: .infinity)
                }
            }
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
