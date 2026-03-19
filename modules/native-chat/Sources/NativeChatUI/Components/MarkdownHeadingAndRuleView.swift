import SwiftUI

// MARK: - Heading View

struct HeadingView: View {
    let level: Int
    let text: String

    var body: some View {
        Group {
            if let attributed = parsedHeadingText {
                Text(attributed)
            } else {
                Text(text)
            }
        }
        .font(fontForLevel)
        .fontWeight(weightForLevel)
        .textSelection(.enabled)
        .padding(.top, topPadding)
        .padding(.bottom, 2)
    }

    private var parsedHeadingText: AttributedString? {
        do {
            return try AttributedString(
                markdown: text,
                options: .init(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace,
                    failurePolicy: .returnPartiallyParsedIfPossible
                )
            )
        } catch {
            return nil
        }
    }

    private var fontForLevel: Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        case 4: .headline
        default: .subheadline
        }
    }

    private var weightForLevel: Font.Weight {
        switch level {
        case 1: .bold
        case 2: .bold
        case 3: .semibold
        case 4: .semibold
        default: .medium
        }
    }

    private var topPadding: CGFloat {
        switch level {
        case 1: 12
        case 2: 10
        case 3: 8
        default: 6
        }
    }
}

// MARK: - Horizontal Rule View

struct HorizontalRuleView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule(style: .continuous)
            .fill(ruleColor)
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private var ruleColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.14)
    }
}
