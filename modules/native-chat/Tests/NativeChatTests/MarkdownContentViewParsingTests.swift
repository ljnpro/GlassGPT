import XCTest
@testable import NativeChat

@MainActor
final class MarkdownContentViewParsingTests: XCTestCase {
    func testParseInlineSegmentsExtractsInlineLatexAndPreservesEscapedDollarText() {
        let segments = makeView().parseInlineSegments(#"alpha $x^2$ beta \(y + z\) cost \$5"#)

        XCTAssertEqual(
            inlineSegmentDescriptions(segments),
            [
                "text(alpha )",
                "latex(x^2)",
                "text( beta )",
                "latex(y + z)",
                #"text( cost \$5)"#
            ]
        )
    }

    func testDetectHeadingRequiresSpaceAndNonEmptyText() {
        let view = makeView()

        XCTAssertEqual(view.detectHeading("### Title")?.level, 3)
        XCTAssertEqual(view.detectHeading("### Title")?.text, "Title")
        XCTAssertNil(view.detectHeading("###Title"))
        XCTAssertNil(view.detectHeading("### "))
        XCTAssertNil(view.detectHeading("plain text"))
    }

    func testIsHorizontalRuleAcceptsSingleRepeatedMarkerWithSpaces() {
        let view = makeView()

        XCTAssertTrue(view.isHorizontalRule("---"))
        XCTAssertTrue(view.isHorizontalRule("* * *"))
        XCTAssertTrue(view.isHorizontalRule("_ _ _"))
        XCTAssertFalse(view.isHorizontalRule("-*-"))
        XCTAssertFalse(view.isHorizontalRule("--"))
    }

    func testParseBlocksSplitsStructuralMarkdownBlocksInOrder() throws {
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

        XCTAssertEqual(parts.map(\.id), Array(0..<parts.count))
        XCTAssertEqual(parts.count, 6)

        let heading = try XCTUnwrap(headingPart(parts[0]))
        XCTAssertEqual(heading.level, 1)
        XCTAssertEqual(heading.text, "Title")

        XCTAssertEqual(
            inlineSegmentDescriptions(try richTextSegments(parts[1])),
            ["text(Lead with )", "latex(x)", "text(.)"]
        )

        XCTAssertTrue(isHorizontalRule(parts[2]))

        let codeBlock = try XCTUnwrap(codeBlockPart(parts[3]))
        XCTAssertEqual(codeBlock.language, "swift")
        XCTAssertEqual(codeBlock.code, "print(\"hi\")\n")

        XCTAssertEqual(try XCTUnwrap(latexBlockContent(parts[4])), "a+b")
        XCTAssertEqual(inlineSegmentDescriptions(try richTextSegments(parts[5])), ["text(\nTail)"])
    }

    func testParseBlocksLeavesUnclosedCodeFenceAsTrailingRichText() throws {
        let input = """
        Before
        ```swift
        let value = 1
        """

        let parts = makeView().parseBlocks(input)

        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(
            inlineSegmentDescriptions(try richTextSegments(parts[0])),
            ["text(Before\n)"]
        )
        XCTAssertEqual(
            inlineSegmentDescriptions(try richTextSegments(parts[1])),
            ["text(```swift\nlet value = 1)"]
        )
    }

    private func makeView() -> MarkdownContentView {
        MarkdownContentView(text: "")
    }

    private func inlineSegmentDescriptions(_ segments: [InlineSegment]) -> [String] {
        segments.map { segment in
            switch segment {
            case let .text(text):
                return "text(\(text))"
            case let .latexInline(latex):
                return "latex(\(latex))"
            }
        }
    }

    private func richTextSegments(
        _ part: BlockPart,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [InlineSegment] {
        guard case let .richText(_, segments) = part else {
            XCTFail("Expected rich text block", file: file, line: line)
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
}
