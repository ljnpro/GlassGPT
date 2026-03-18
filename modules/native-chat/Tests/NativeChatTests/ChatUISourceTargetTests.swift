import SwiftUI
import XCTest
import ChatUIComponents

@MainActor
final class ChatUISourceTargetTests: XCTestCase {
    func testRichTextBuilderPreservesLinksAndRemovesMarkdownMarkers() {
        let richText = RichTextAttributedStringBuilder.parseRichText(
            "Visit [OpenAI](https://openai.com) and **ship** _cleanly_."
        )
        let rendered = String(richText.characters)

        XCTAssertEqual(rendered, "Visit OpenAI and ship cleanly.")
        XCTAssertTrue(richText.runs.contains(where: { $0.link?.absoluteString == "https://openai.com" }))
    }

    func testStreamingRichTextBuilderResolvesInlineCode() {
        let richText = RichTextAttributedStringBuilder.parseStreamingText("Use `swift test` for coverage.")
        let rendered = String(richText.characters)

        XCTAssertEqual(rendered, "Use swift test for coverage.")
    }

    func testStableRoundedGlassModifierHostsWithoutCrashing() {
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

        XCTAssertNotNil(controller.view)
    }

    func testStaticRoundedGlassShellModifierHostsWithoutCrashing() {
        let controller = UIHostingController(
            rootView: Text("Shell").modifier(
                StaticRoundedGlassShellModifier(
                    cornerRadius: 14,
                    innerInset: 1.5
                )
            )
        )

        controller.loadViewIfNeeded()

        XCTAssertNotNil(controller.view)
    }
}
