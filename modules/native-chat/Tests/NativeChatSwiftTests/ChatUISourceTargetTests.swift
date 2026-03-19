import ChatUIComponents
import Foundation
import SwiftUI
import Testing
import UIKit

@MainActor
struct ChatUISourceTargetTests {
    @Test func `rich text builder preserves links and removes markdown markers`() {
        let richText = RichTextAttributedStringBuilder.parseRichText(
            "Visit [OpenAI](https://openai.com) and **ship** _cleanly_."
        )
        let rendered = String(richText.characters)

        #expect(rendered == "Visit OpenAI and ship cleanly.")
        #expect(richText.runs.contains(where: { $0.link?.absoluteString == "https://openai.com" }))
    }

    @Test func `streaming rich text builder resolves inline code`() {
        let richText = RichTextAttributedStringBuilder.parseStreamingText("Use `swift test` for coverage.")
        let rendered = String(richText.characters)

        #expect(rendered == "Use swift test for coverage.")
    }

    @Test func `stable rounded glass modifier hosts without crashing`() {
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

    @Test func `static rounded glass shell modifier hosts without crashing`() {
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
