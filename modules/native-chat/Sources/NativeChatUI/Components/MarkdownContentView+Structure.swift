import Foundation

package extension MarkdownContentView {
    /// Detects a Markdown heading (e.g. `## Title`) and returns its level and text, or nil.
    func detectHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        let chars = Array(line)
        while level < chars.count, level < 6, chars[level] == "#" {
            level += 1
        }
        guard level > 0 else { return nil }
        guard level < chars.count, chars[level] == " " else { return nil }
        let text = String(chars[(level + 1)...]).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    /// Returns `true` if the line is a Markdown horizontal rule (e.g. `---`, `***`, `___`).
    func isHorizontalRule(_ line: String) -> Bool {
        let condensed = line.replacingOccurrences(of: " ", with: "")
        guard condensed.count >= 3 else { return false }
        guard let marker = condensed.first else { return false }
        guard marker == "-" || marker == "_" || marker == "*" else { return false }
        return condensed.allSatisfy { $0 == marker }
    }
}
