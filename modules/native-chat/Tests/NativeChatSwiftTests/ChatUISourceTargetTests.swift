import Foundation
import Testing
import SwiftUI
import UIKit
import ChatUIComponents

@MainActor
struct ChatUISourceTargetTests {
    @Test func richTextBuilderPreservesLinksAndRemovesMarkdownMarkers() {
        let richText = RichTextAttributedStringBuilder.parseRichText(
            "Visit [OpenAI](https://openai.com) and **ship** _cleanly_."
        )
        let rendered = String(richText.characters)

        #expect(rendered == "Visit OpenAI and ship cleanly.")
        #expect(richText.runs.contains(where: { $0.link?.absoluteString == "https://openai.com" }))
    }

    @Test func streamingRichTextBuilderResolvesInlineCode() {
        let richText = RichTextAttributedStringBuilder.parseStreamingText("Use `swift test` for coverage.")
        let rendered = String(richText.characters)

        #expect(rendered == "Use swift test for coverage.")
    }

    @Test func stableRoundedGlassModifierHostsWithoutCrashing() {
        let controller = UIHostingController(
            rootView: Text("Glass").modifier(
                StableRoundedGlassModifier(
                    cornerRadius: 18,
                    interactive: true,
                    innerInset: 1.0,
                    stableFillOpacity: 0.08
                )
            )
        )

        controller.loadViewIfNeeded()

        #expect(controller.view != nil)
    }

    @Test func staticRoundedGlassShellModifierHostsWithoutCrashing() {
        let controller = UIHostingController(
            rootView: Text("Shell").modifier(
                StaticRoundedGlassShellModifier(
                    cornerRadius: 14,
                    innerInset: 1.5
                )
            )
        )

        controller.loadViewIfNeeded()

        #expect(controller.view != nil)
    }
}
