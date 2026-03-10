import SwiftUI
import Highlightr

@MainActor
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var isCopied = false
    @Environment(\.colorScheme) private var colorScheme

    // Shared highlighter instance (created lazily on main actor)
    @MainActor
    private static var highlightr: Highlightr? = Highlightr()

    private var highlightedCode: AttributedString {
        let lang = language?.lowercased() ?? "plaintext"
        let themeName = colorScheme == .dark ? "atom-one-dark" : "atom-one-light"

        if let h = Self.highlightr {
            h.setTheme(to: themeName)
            if let highlighted = h.highlight(code, as: lang, fastRender: true) {
                return AttributedString(highlighted)
            }
        }
        return AttributedString(code)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language label and copy button
            HStack {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    withAnimation(.spring(duration: 0.3)) {
                        isCopied = true
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.spring(duration: 0.3)) {
                            isCopied = false
                        }
                    }
                    HapticService.shared.impact(.light)
                } label: {
                    Label(
                        isCopied ? "Copied" : "Copy",
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2)
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .padding(6)
            }
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlightedCode)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 4)
    }
}
