import Foundation

package extension MarkdownContentView {
    private enum CodeBlockParseResult {
        case block(language: String?, code: String, nextIndex: Int)
        case fallback(nextIndex: Int)
    }

    private enum LatexBlockParseResult {
        case block(content: String, nextIndex: Int)
        case fallback(prefix: String, nextIndex: Int)
    }

    // MARK: - Parsing

    /// First pass: extract code blocks and LaTeX blocks from raw text.
    /// Returns a mix of code/latex blocks and raw text chunks.
    func parseBlocks(_ input: String) -> [BlockPart] {
        let firstPass = parsePrimaryBlocks(input)
        guard !firstPass.isEmpty else {
            return [.richText(id: 0, segments: [.text(input)])]
        }

        let finalParts = expandRichTextParts(firstPass)
        let result = reindexBlockParts(finalParts)
        return result.isEmpty ? [.richText(id: 0, segments: [.text(input)])] : result
    }

    private func parsePrimaryBlocks(_ input: String) -> [BlockPart] {
        var firstPass: [BlockPart] = []
        var inlineBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var index = 0
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        func flushInline() {
            if !inlineBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segments = parseInlineSegments(inlineBuffer)
                firstPass.append(.richText(id: makeID(), segments: segments))
            }
            inlineBuffer = ""
        }

        while index < count {
            if let parsed = consumeCodeBlock(chars, index: index, count: count) {
                flushInline()
                switch parsed {
                case let .block(language, code, nextIndex):
                    firstPass.append(.codeBlock(id: makeID(), language: language, code: code))
                    index = nextIndex
                case let .fallback(nextIndex):
                    inlineBuffer += "```"
                    index = nextIndex
                }
                continue
            }

            if let parsed = consumeEscapedLatexBlock(chars, index: index, count: count) {
                flushInline()
                switch parsed {
                case let .block(content, nextIndex):
                    if !content.isEmpty {
                        firstPass.append(.latexBlock(id: makeID(), content: content))
                    }
                    index = nextIndex
                case let .fallback(prefix, nextIndex):
                    inlineBuffer.append(prefix)
                    index = nextIndex
                }
                continue
            }

            if let parsed = consumeDollarLatexBlock(chars, index: index, count: count) {
                flushInline()
                switch parsed {
                case let .block(content, nextIndex):
                    if !content.isEmpty {
                        firstPass.append(.latexBlock(id: makeID(), content: content))
                    }
                    index = nextIndex
                case let .fallback(prefix, nextIndex):
                    inlineBuffer.append(prefix)
                    index = nextIndex
                }
                continue
            }

            inlineBuffer.append(chars[index])
            index += 1
        }

        flushInline()
        return firstPass
    }

    private func consumeCodeBlock(
        _ chars: [Character],
        index: Int,
        count: Int
    ) -> CodeBlockParseResult? {
        guard index + 2 < count, chars[index] == "`", chars[index + 1] == "`", chars[index + 2] == "`" else {
            return nil
        }

        let start = index + 3
        var languageEnd = start
        while languageEnd < count, chars[languageEnd] != "\n" {
            languageEnd += 1
        }

        let language = String(chars[start ..< languageEnd]).trimmingCharacters(in: .whitespaces)
        let codeStart = min(languageEnd + 1, count)
        var codeEnd = codeStart

        while codeEnd + 2 < count {
            if chars[codeEnd] == "`", chars[codeEnd + 1] == "`", chars[codeEnd + 2] == "`" {
                var nextIndex = codeEnd + 3
                if nextIndex < count, chars[nextIndex] == "\n" {
                    nextIndex += 1
                }
                return .block(
                    language: language.isEmpty ? nil : language,
                    code: String(chars[codeStart ..< codeEnd]),
                    nextIndex: nextIndex
                )
            }
            codeEnd += 1
        }

        return .fallback(nextIndex: start)
    }

    private func consumeEscapedLatexBlock(
        _ chars: [Character],
        index: Int,
        count: Int
    ) -> LatexBlockParseResult? {
        guard index + 1 < count, chars[index] == "\\", chars[index + 1] == "[" else {
            return nil
        }

        let start = index + 2
        var end = start
        while end + 1 < count {
            if chars[end] == "\\", chars[end + 1] == "]" {
                let content = String(chars[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
                return .block(content: content, nextIndex: end + 2)
            }
            end += 1
        }

        return .fallback(prefix: "\\[", nextIndex: start)
    }

    private func consumeDollarLatexBlock(
        _ chars: [Character],
        index: Int,
        count: Int
    ) -> LatexBlockParseResult? {
        guard index + 1 < count, chars[index] == "$", chars[index + 1] == "$" else {
            return nil
        }

        let start = index + 2
        var end = start
        while end + 1 < count {
            if chars[end] == "$", chars[end + 1] == "$" {
                let content = String(chars[start ..< end]).trimmingCharacters(in: .whitespacesAndNewlines)
                return .block(content: content, nextIndex: end + 2)
            }
            end += 1
        }

        return .fallback(prefix: "$$", nextIndex: start)
    }

    private func expandRichTextParts(_ firstPass: [BlockPart]) -> [BlockPart] {
        var finalParts: [BlockPart] = []
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        func flushLineBuffer(_ lineBuffer: inout [String]) {
            let joined = lineBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segs = parseInlineSegments(joined)
                finalParts.append(.richText(id: makeID(), segments: segs))
            }
            lineBuffer = []
        }

        for part in firstPass {
            switch part {
            case let .richText(_, segments):
                let rawText = segments.map { seg in
                    switch seg {
                    case let .text(str): str
                    case let .latexInline(latex): "$\(latex)$"
                    }
                }.joined()

                let lines = rawText.components(separatedBy: "\n")
                var lineBuffer: [String] = []
                var lineIndex = 0

                while lineIndex < lines.count {
                    let line = lines[lineIndex]
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let tableParse = parseTable(lines: lines, startingAt: lineIndex) {
                        flushLineBuffer(&lineBuffer)
                        finalParts.append(.table(id: makeID(), table: tableParse.table))
                        lineIndex = tableParse.nextIndex
                    } else if let headingMatch = detectHeading(trimmed) {
                        flushLineBuffer(&lineBuffer)
                        finalParts.append(.heading(id: makeID(), level: headingMatch.level, text: headingMatch.text))
                    } else if isHorizontalRule(trimmed) {
                        flushLineBuffer(&lineBuffer)
                        finalParts.append(.horizontalRule(id: makeID()))
                    } else {
                        lineBuffer.append(line)
                    }
                    lineIndex += 1
                }
                flushLineBuffer(&lineBuffer)

            default:
                finalParts.append(part)
            }
        }

        return finalParts
    }

    private func reindexBlockParts(_ parts: [BlockPart]) -> [BlockPart] {
        var result: [BlockPart] = []
        var finalID = 0

        for part in parts {
            switch part {
            case let .richText(_, segments):
                result.append(.richText(id: finalID, segments: segments))
            case let .heading(_, level, text):
                result.append(.heading(id: finalID, level: level, text: text))
            case .horizontalRule:
                result.append(.horizontalRule(id: finalID))
            case let .latexBlock(_, content):
                result.append(.latexBlock(id: finalID, content: content))
            case let .codeBlock(_, language, code):
                result.append(.codeBlock(id: finalID, language: language, code: code))
            case let .table(_, table):
                result.append(.table(id: finalID, table: table))
            }
            finalID += 1
        }

        return result
    }
}
