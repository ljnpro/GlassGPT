import ChatDomain
import Foundation
import Testing
@testable import ConversationSurfaceLogic
@testable import NativeChatUI

@Suite(.tags(.presentation))
struct NativeChatComponentLogicCoverageTests {
    @Test func `citation link card model deduplicates urls and derives fallback titles`() {
        let citations = [
            URLCitation(url: "https://www.example.com/page", title: "", startIndex: 0, endIndex: 4),
            URLCitation(url: "https://www.example.com/page", title: "Duplicate", startIndex: 5, endIndex: 9),
            URLCitation(url: "https://docs.example.org/path", title: "Docs", startIndex: 10, endIndex: 14)
        ]

        let models = CitationLinkCardModel.makeModels(from: citations)

        #expect(models.count == 2)
        #expect(models[0].index == 1)
        #expect(models[0].domain == "example.com")
        #expect(models[0].title == "example.com")
        #expect(models[0].accessibilityLabel == "Source 1: example.com")
        #expect(models[1].title == "Docs")
        #expect(CitationLinkCardModel.domain(for: "not-a-url") == "not-a-url")
    }

    @Test func `markdown table layout computes column widths padding and alignments`() {
        let table = MarkdownTable(
            headers: [[.text("Column A")], [.text("Column B")]],
            rows: [
                [[.text("short")], [.text("a much longer row of markdown content")]],
                [[.latexInline("x^2")]]
            ],
            alignments: [.leading, .trailing]
        )

        let phoneLayout = MarkdownTableLayout(table: table, idiom: .phone)
        let padLayout = MarkdownTableLayout(table: table, idiom: .pad)

        #expect(phoneLayout.columnWidths.count == 2)
        #expect(phoneLayout.minimumTableWidth > 0)
        #expect(padLayout.columnWidths[0] >= phoneLayout.columnWidths[0])
        #expect(phoneLayout.paddedCells(for: table.rows[1]).count == 2)
        #expect(phoneLayout.alignment(forColumnAt: 0) == .leading)
        #expect(phoneLayout.alignment(forColumnAt: 1) == .trailing)
        #expect(MarkdownTableLayout.textLength(for: [.text(String(repeating: "x", count: 120))]) == 80)
        #expect(MarkdownTableLayout.textLength(for: [.text("  hello\nworld  ")]) == 11)
    }

    @Test func `markdown parser extracts inline latex headings rules tables and code blocks`() throws {
        let inline = MarkdownParser.parseInlineSegments(#"Before \(x^2\) and $y$ after"#)
        #expect(inline == [.text("Before "), .latexInline("x^2"), .text(" and "), .latexInline("y"), .text(" after")])

        #expect(MarkdownParser.detectHeading("### Release notes")?.level == 3)
        #expect(MarkdownParser.detectHeading("No heading") == nil)
        #expect(MarkdownParser.isHorizontalRule("---"))
        #expect(MarkdownParser.isHorizontalRule(":--") == false)

        let lines = [
            "| Name | Value |",
            "| :--- | ---: |",
            "| One | 1 |",
            "| Two | 2 |"
        ]
        let parsedTable = try #require(MarkdownParser.parseTable(lines: lines, startingAt: 0))
        #expect(parsedTable.table.alignments == [.leading, .trailing])
        #expect(parsedTable.table.rows.count == 2)

        let blocks = MarkdownParser.parseBlocks(
            """
            # Title

            Intro with $z$.

            | Col | Val |
            | --- | --- |
            | A | 1 |

            ```swift
            print(1)
            ```

            $$x+y$$
            """
        )
        #expect(blocks.contains { part in
            if case let .heading(_, level, text) = part {
                return level == 1 && text == "Title"
            }
            return false
        })
        #expect(blocks.contains { part in
            if case .table = part {
                return true
            }
            return false
        })
        #expect(blocks.contains { part in
            if case let .codeBlock(_, language, code) = part {
                return language == "swift" && code.contains("print(1)")
            }
            return false
        })
        #expect(blocks.contains { part in
            if case let .latexBlock(_, content) = part {
                return content == "x+y"
            }
            return false
        })
    }

    @Test func `detached streaming bubble content state captures indicator transitions`() {
        let activeCalls = [
            ToolCallInfo(id: "web", type: .webSearch, status: .searching),
            ToolCallInfo(id: "file", type: .fileSearch, status: .fileSearching),
            ToolCallInfo(id: "code-1", type: .codeInterpreter, status: .interpreting),
            ToolCallInfo(id: "code-2", type: .codeInterpreter, status: .completed, code: "print(1)", results: ["1"])
        ]
        let liveCitations = [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)]

        let thinkingState = DetachedStreamingBubbleContentState(
            activeToolCalls: activeCalls,
            currentThinkingText: "",
            currentStreamingText: "",
            isThinking: true,
            liveCitations: liveCitations
        )
        #expect(thinkingState.hasActiveWebSearch)
        #expect(thinkingState.hasActiveCodeInterpreter)
        #expect(thinkingState.hasActiveFileSearch)
        #expect(thinkingState.completedCodeCalls.count == 1)
        #expect(thinkingState.showsThinkingIndicator)
        #expect(!thinkingState.showsTypingIndicator)
        #expect(thinkingState.showsCitations)

        let typingState = DetachedStreamingBubbleContentState(
            activeToolCalls: [ToolCallInfo(id: "done", type: .codeInterpreter, status: .completed)],
            currentThinkingText: "",
            currentStreamingText: "",
            isThinking: false,
            liveCitations: []
        )
        #expect(!typingState.showsThinkingIndicator)
        #expect(typingState.showsTypingIndicator)
        #expect(!typingState.showsCitations)
    }
}
