import Foundation

package extension MarkdownContentView {
    /// Splits a raw text line into plain text and inline LaTeX segments.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func parseInlineSegments(_ input: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var textBuffer = ""
        let chars = Array(input)
        let count = chars.count
        var index = 0

        func flushText() {
            if !textBuffer.isEmpty {
                segments.append(.text(textBuffer))
                textBuffer = ""
            }
        }

        while index < count {
            if index + 1 < count, chars[index] == "\\", chars[index + 1] == "(" {
                flushText()
                let start = index + 2
                var end = start
                var found = false
                while end + 1 < count {
                    if chars[end] == "\\", chars[end + 1] == ")" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found {
                    let latex = String(chars[start ..< end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    index = end + 2
                } else {
                    textBuffer.append("\\(")
                    index = start
                }
                continue
            }

            if chars[index] == "$", index == 0 || chars[index - 1] != "\\" {
                let start = index + 1
                var end = start
                var found = false
                while end < count, chars[end] != "\n" {
                    if chars[end] == "$", end == start || chars[end - 1] != "\\" {
                        found = true
                        break
                    }
                    end += 1
                }

                if found, end > start {
                    flushText()
                    let latex = String(chars[start ..< end]).trimmingCharacters(in: .whitespaces)
                    if !latex.isEmpty {
                        segments.append(.latexInline(latex))
                    }
                    index = end + 1
                } else {
                    textBuffer.append(chars[index])
                    index += 1
                }
                continue
            }

            textBuffer.append(chars[index])
            index += 1
        }

        flushText()
        return segments
    }
}
