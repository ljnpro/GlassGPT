import Foundation

extension MarkdownParser {
    static func expandRichTextParts(_ firstPass: [BlockPart]) -> [BlockPart] {
        var finalParts: [BlockPart] = []
        var nextID = 0

        func makeID() -> Int {
            defer { nextID += 1 }
            return nextID
        }

        func flushLineBuffer(_ lineBuffer: inout [String]) {
            let joined = lineBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let segments = parseInlineSegments(joined)
                finalParts.append(.richText(id: makeID(), segments: segments))
            }
            lineBuffer = []
        }

        for part in firstPass {
            switch part {
            case let .richText(_, segments):
                let rawText = segments.map { segment in
                    switch segment {
                    case let .text(str):
                        str
                    case let .latexInline(latex):
                        "$\(latex)$"
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

    static func reindexBlockParts(_ parts: [BlockPart]) -> [BlockPart] {
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
