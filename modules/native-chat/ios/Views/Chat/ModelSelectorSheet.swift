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
        NavigationStack {
            Form {
                Section("Model") {
                    ForEach(ModelType.allCases) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.body.weight(.medium))

                                Text(modelDescription(for: model))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if model == selectedModel {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let previousModel = selectedModel
                            selectedModel = model

                            // If current effort is not available for the new model, reset to default
                            if !model.availableEfforts.contains(reasoningEffort) {
                                reasoningEffort = model.defaultEffort
                            }

                            if model != previousModel {
                                HapticService.shared.selection()
                            }
                        }
                    }
                }

                Section("Reasoning Effort") {
                    let availableEfforts = selectedModel.availableEfforts

                    ForEach(availableEfforts) { effort in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effort.displayName)
                                    .font(.body.weight(.medium))

                                Text(effortDescription(for: effort))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if effort == reasoningEffort {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if effort != reasoningEffort {
                                reasoningEffort = effort
                                HapticService.shared.selection()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func modelDescription(for model: ModelType) -> String {
        switch model {
        case .gpt5_4: return "Fast and capable for everyday tasks"
        case .gpt5_4_pro: return "Most powerful model for complex reasoning"
        }
    }

    private func effortDescription(for effort: ReasoningEffort) -> String {
        switch effort {
        case .none: return "No reasoning — fastest responses"
        case .low: return "Light reasoning — quick analysis"
        case .medium: return "Balanced reasoning and speed"
        case .high: return "Deep reasoning — most thorough"
        case .xhigh: return "Maximum reasoning — longest, most detailed"
        }
    }
}
