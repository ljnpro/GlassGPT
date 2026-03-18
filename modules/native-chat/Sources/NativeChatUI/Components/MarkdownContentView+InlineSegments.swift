import Foundation

extension MarkdownContentView {
    package func parseInlineSegments(_ input: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var textBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var i = 0

        func flushText() {
            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer))
                textBuffer = ""
            }
        }

        while i < count {
            if i + 1 < count && chars[i] == "\\" && chars[i + 1] == "(" {
                flushText()
                let start = i + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\" && chars[end + 1] == ")" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    i = end + 2
                } else {
                    textBuffer.append("\\(")
                    i = start
                }
                continue
            }

            if chars[i] == "$" && (i == 0 || chars[i - 1] != "\\") {
                let start = i + 1
                var end = start
                var found = false
                while end < count && chars[end] != "\n" {
                    if chars[end] == "$" && (end == start || chars[end - 1] != "\\") {
                        found = true
                        break
                    }
                    end += 1
                }

                if found && end > start {
                    flushText()
                    let latex = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    i = end + 1
                } else {
                    textBuffer.append(chars[i])
                    i += 1
                }
                continue
            }

            textBuffer.append(chars[i])
            i += 1
        }

        flushText()
        return segments
    }
}
