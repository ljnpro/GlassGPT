import Foundation

extension MarkdownParser {
    private enum CodeBlockParseResult {
        case block(language: String?, code: String, nextIndex: Int)
        case fallback(nextIndex: Int)
    }

    private enum LatexBlockParseResult {
        case block(content: String, nextIndex: Int)
        case fallback(prefix: String, nextIndex: Int)
    }

    static func parsePrimaryBlocks(_ input: String) -> [BlockPart] {
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

    private static func consumeCodeBlock(
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

    private static func consumeEscapedLatexBlock(
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

    private static func consumeDollarLatexBlock(
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
}
