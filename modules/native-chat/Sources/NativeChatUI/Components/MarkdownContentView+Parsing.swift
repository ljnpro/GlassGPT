import Foundation

extension MarkdownContentView {

    // MARK: - Parsing

    /// First pass: extract code blocks and LaTeX blocks from raw text.
    /// Returns a mix of code/latex blocks and raw text chunks.
    package func parseBlocks(_ input: String) -> [BlockPart] {
        var firstPass: [BlockPart] = []
        var inlineBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0
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

        while i < count {
            if i + 2 < count && chars[i] == "`" && chars[i + 1] == "`" && chars[i + 2] == "`" {
                flushInline()
                let start = i + 3
                var langEnd = start
                while langEnd < count && chars[langEnd] != "\n" {
                    langEnd += 1
                }

                let lang = String(chars[start..<langEnd]).trimmingCharacters(in: .whitespaces)
                let codeStart = min(langEnd + 1, count)

                var codeEnd = codeStart
                var found = false
                while codeEnd + 2 < count {
                    if chars[codeEnd] == "`" && chars[codeEnd + 1] == "`" && chars[codeEnd + 2] == "`" {
                        found = true
                        break
                    }
                    codeEnd += 1
                }

                if found {
                    let code = String(chars[codeStart..<codeEnd])
                    firstPass.append(.codeBlock(id: makeID(), language: lang.isEmpty ? nil : lang, code: code))
                    i = codeEnd + 3
                    if i < count && chars[i] == "\n" {
                        i += 1
                    }
                } else {
                    inlineBuffer += "```"
                    i = start
                }
                continue
            }

            if i + 1 < count && chars[i] == "\\" && chars[i + 1] == "[" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end + 1] == "]" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        firstPass.append(.latexBlock(id: makeID(), content: latex))
                    }
                    i = end + 2
                } else {
                    inlineBuffer.append("\\[")
                    i = start
                }
                continue
            }

            if i + 1 < count && chars[i] == "$" && chars[i + 1] == "$" {
                flushInline()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "$" && chars[end + 1] == "$" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        firstPass.append(.latexBlock(id: makeID(), content: latex))
                    }
                    i = end + 2
                } else {
                    inlineBuffer.append("$$")
                    i = start
                }
                continue
            }

            inlineBuffer.append(chars[i])
            i += 1
        }

        flushInline()

        if firstPass.isEmpty {
            return [.richText(id: 0, segments: [.text(input)])]
        }

        var finalParts: [BlockPart] = []
        for part in firstPass {
            switch part {
            case let .richText(_, segments):
                let rawText = segments.map { seg in
                    switch seg {
                    case let .text(str): return str
                    case let .latexInline(latex): return "$\(latex)$"
                    }
                }.joined()

                let lines = rawText.components(separatedBy: "\n")
                var lineBuffer: [String] = []

                func flushLineBuffer() {
                    let joined = lineBuffer.joined(separator: "\n")
                    if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let segs = parseInlineSegments(joined)
                        finalParts.append(.richText(id: makeID(), segments: segs))
                    }
                    lineBuffer = []
                }

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if let headingMatch = detectHeading(trimmed) {
                        flushLineBuffer()
                        finalParts.append(.heading(id: makeID(), level: headingMatch.level, text: headingMatch.text))
                    } else if isHorizontalRule(trimmed) {
                        flushLineBuffer()
                        finalParts.append(.horizontalRule(id: makeID()))
                    } else {
                        lineBuffer.append(line)
                    }
                }
                flushLineBuffer()

            default:
                finalParts.append(part)
            }
        }

        var result: [BlockPart] = []
        var finalID = 0
        for part in finalParts {
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
            }
            finalID += 1
        }

        return result.isEmpty ? [.richText(id: 0, segments: [.text(input)])] : result
    }
}
