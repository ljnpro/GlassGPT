import Foundation
import NativeChatUI
import Testing
@testable import NativeChatComposition

@MainActor
struct MarkdownContentViewParsingTests {
    @Test func `parse inline segments extracts inline latex and preserves escaped dollar text`() {
        let segments = makeView().parseInlineSegments(#"alpha $x^2$ beta \(y + z\) cost \$5"#)

        #expect(
            inlineSegmentDescriptions(segments) ==
                [
                    "text(alpha )",
                    "latex(x^2)",
                    "text( beta )",
                    "latex(y + z)",
                    #"text( cost \$5)"#
                ]
        )
    }

    @Test func `detect heading requires space and non empty text`() {
        let view = makeView()

        #expect(view.detectHeading("### Title")?.level == 3)
        #expect(view.detectHeading("### Title")?.text == "Title")
        #expect(view.detectHeading("###Title") == nil)
        #expect(view.detectHeading("### ") == nil)
        #expect(view.detectHeading("plain text") == nil)
    }

    @Test func `is horizontal rule accepts single repeated marker with spaces`() {
        let view = makeView()

        #expect(view.isHorizontalRule("---"))
        #expect(view.isHorizontalRule("* * *"))
        #expect(view.isHorizontalRule("_ _ _"))
        #expect(!view.isHorizontalRule("-*-"))
        #expect(!view.isHorizontalRule("--"))
    }

    @Test func `parse blocks splits structural markdown blocks in order`() throws {
        let input = """
        # Title
        Lead with $x$.
        ---
        ```swift
        print("hi")
        ```
        $$
        a+b
        $$
        Tail
        """

        let parts = makeView().parseBlocks(input)

        #expect(parts.map(\.id) == Array(0 ..< parts.count))
        #expect(parts.count == 6)

        let heading = try #require(headingPart(parts[0]))
        #expect(heading.level == 1)
        #expect(heading.text == "Title")

        #expect(
            try inlineSegmentDescriptions(richTextSegments(parts[1])) ==
                ["text(Lead with )", "latex(x)", "text(.)"]
        )

        #expect(isHorizontalRule(parts[2]))

        let codeBlock = try #require(codeBlockPart(parts[3]))
        #expect(codeBlock.language == "swift")
        #expect(codeBlock.code == "print(\"hi\")\n")

        #expect(try #require(latexBlockContent(parts[4])) == "a+b")
        #expect(try inlineSegmentDescriptions(richTextSegments(parts[5])) == ["text(\nTail)"])
    }

    @Test func `parse blocks leaves unclosed code fence as trailing rich text`() throws {
        let input = """
        Before
        ```swift
        let value = 1
        """

        let parts = makeView().parseBlocks(input)

        #expect(parts.count == 2)
        #expect(
            try inlineSegmentDescriptions(richTextSegments(parts[0])) ==
                ["text(Before\n)"]
        )
        #expect(
            try inlineSegmentDescriptions(richTextSegments(parts[1])) ==
                ["text(```swift\nlet value = 1)"]
        )
    }

    @Test func `parse blocks extracts pipe tables with alignment`() throws {
        let input = """
        | Name | Score | Notes |
        | :--- | ---: | :---: |
        | Alpha | 10 | **Ready** |
        | Beta | 8 | `Hold` |
        """

        let parts = makeView().parseBlocks(input)

        #expect(parts.count == 1)
        let table = try #require(tablePart(parts[0]))
        #expect(table.alignments.count == 3)
        #expect(table.alignments[0] == .leading)
        #expect(table.alignments[1] == .trailing)
        #expect(table.alignments[2] == .center)
        #expect(table.rows.count == 2)
    }

    private func makeView() -> MarkdownContentView {
        MarkdownContentView(text: "")
    }

    private func inlineSegmentDescriptions(_ segments: [InlineSegment]) -> [String] {
        segments.map { segment in
            switch segment {
            case let .text(text):
                "text(\(text))"
            case let .latexInline(latex):
                "latex(\(latex))"
            }
        }
    }

    private func richTextSegments(
        _ part: BlockPart
    ) throws -> [InlineSegment] {
        guard case let .richText(_, segments) = part else {
            Issue.record("Expected rich text block")
            return []
        }
        return segments
    }

    private func headingPart(_ part: BlockPart) -> (level: Int, text: String)? {
        guard case let .heading(_, level, text) = part else {
            return nil
        }
        return (level, text)
    }

    private func isHorizontalRule(_ part: BlockPart) -> Bool {
        guard case .horizontalRule = part else {
            return false
        }
        return true
    }

    private func codeBlockPart(_ part: BlockPart) -> (language: String?, code: String)? {
        guard case let .codeBlock(_, language, code) = part else {
            return nil
        }
        return (language, code)
    }

    private func latexBlockContent(_ part: BlockPart) -> String? {
        guard case let .latexBlock(_, content) = part else {
            return nil
        }
        return content
    }

    private func tablePart(_ part: BlockPart) -> MarkdownTable? {
        guard case let .table(_, table) = part else {
            return nil
        }
        return table
    }
}
