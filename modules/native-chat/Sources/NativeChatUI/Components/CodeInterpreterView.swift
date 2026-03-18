import ChatDomain
import ChatUIComponents
import SwiftUI

/// Animated indicator shown when the model is executing code via the code interpreter.
package struct CodeInterpreterIndicator: View {
    package init() {}

    package var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating)

            Text("Running code…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .singleSurfaceGlass(
            cornerRadius: 999,
            stableFillOpacity: 0.01,
            tintOpacity: 0.022,
            borderWidth: 0.75,
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
    }
}

/// Displays a completed code interpreter call with expandable code and output.
package struct CodeInterpreterResultView: View {
    let toolCall: ToolCallInfo
    @State private var isExpanded = false

    package init(toolCall: ToolCallInfo) {
        self.toolCall = toolCall
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)

                    Text("Code Executed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Code block
                    if let code = toolCall.code, !code.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PYTHON")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(code)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                            }
                        }
                        .padding(.vertical, 6)
                        .singleSurfaceGlass(
                            cornerRadius: 8,
                            stableFillOpacity: 0.006,
                            tintOpacity: 0.022,
                            borderWidth: 0.7,
                            darkBorderOpacity: 0.13,
                            lightBorderOpacity: 0.075
                        )
                        .padding(.horizontal, 12)
                    }

                    // Output
                    if let results = toolCall.results, !results.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OUTPUT")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)

                            ForEach(results, id: \.self) { result in
                                Text(result)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 10)
                            }
                        }
                        .padding(.vertical, 6)
                        .singleSurfaceGlass(
                            cornerRadius: 8,
                            stableFillOpacity: 0.006,
                            tintOpacity: 0.022,
                            borderWidth: 0.7,
                            darkBorderOpacity: 0.13,
                            lightBorderOpacity: 0.075
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .singleSurfaceGlass(
            cornerRadius: 12,
            stableFillOpacity: 0.01,
            tintOpacity: 0.024,
            borderWidth: 0.75,
            darkBorderOpacity: 0.14,
            lightBorderOpacity: 0.08
        )
    }
}
