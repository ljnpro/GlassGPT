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
            .padding(.bottom, 12)

            // Content
            VStack(spacing: 16) {
                // Model selection
                VStack(alignment: .leading, spacing: 8) {
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

                // Reasoning Effort
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reasoning Effort")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    let efforts = selectedModel.availableEfforts
                    // Use a wrapping layout for effort chips
                    FlowLayout(spacing: 8) {
                        ForEach(efforts) { effort in
                            effortChip(effort)
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

    // MARK: - Effort Chip

    private func effortChip(_ effort: ReasoningEffort) -> some View {
        let isSelected = effort == reasoningEffort

        return Button {
            if effort != reasoningEffort {
                reasoningEffort = effort
                HapticService.shared.selection()
            }
        } label: {
            Text(effort.displayName)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
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

// MARK: - Flow Layout (for wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private struct ArrangeResult {
        var size: CGSize
        var positions: [CGPoint]
        var sizes: [CGSize]
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if x + size.width > maxWidth && x > 0 {
                // Move to next row
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = y + rowHeight
        }

        return ArrangeResult(
            size: CGSize(width: totalWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }
}
