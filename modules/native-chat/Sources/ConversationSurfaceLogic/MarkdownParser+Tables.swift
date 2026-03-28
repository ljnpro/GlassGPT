import Foundation

package extension MarkdownParser {
    static func detectHeading(_ line: String) -> (level: Int, text: String)? {
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

    static func isHorizontalRule(_ line: String) -> Bool {
        let condensed = line.replacingOccurrences(of: " ", with: "")
        guard condensed.count >= 3 else { return false }
        guard let marker = condensed.first else { return false }
        guard marker == "-" || marker == "_" || marker == "*" else { return false }
        return condensed.allSatisfy { $0 == marker }
    }

    static func parseTable(
        lines: [String],
        startingAt startIndex: Int
    ) -> (table: MarkdownTable, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else {
            return nil
        }

        let headerCells = tableCells(from: lines[startIndex])
        guard headerCells.count > 1 else {
            return nil
        }

        guard let alignments = tableAlignments(from: lines[startIndex + 1], expectedCount: headerCells.count) else {
            return nil
        }

        var rows: [[[InlineSegment]]] = []
        var index = startIndex + 2

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                break
            }

            let rowCells = tableCells(from: line)
            guard rowCells.count == headerCells.count else {
                break
            }

            rows.append(rowCells.map(parseInlineSegments))
            index += 1
        }

        return (
            MarkdownTable(
                headers: headerCells.map(parseInlineSegments),
                rows: rows,
                alignments: alignments
            ),
            max(index - 1, startIndex + 1)
        )
    }

    private static func tableCells(from line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else {
            return []
        }

        var content = trimmed
        if content.hasPrefix("|") {
            content.removeFirst()
        }
        if content.hasSuffix("|") {
            content.removeLast()
        }

        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return cells.count > 1 ? cells : []
    }

    private static func tableAlignments(
        from separatorLine: String,
        expectedCount: Int
    ) -> [MarkdownTableAlignment]? {
        let cells = tableCells(from: separatorLine)
        guard cells.count == expectedCount else {
            return nil
        }

        let alignments = cells.compactMap { cell -> MarkdownTableAlignment? in
            let condensed = cell.replacingOccurrences(of: " ", with: "")
            guard condensed.count >= 3 else {
                return nil
            }
            guard condensed.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            let leadingColon = condensed.hasPrefix(":")
            let trailingColon = condensed.hasSuffix(":")
            switch (leadingColon, trailingColon) {
            case (true, true):
                return .center
            case (false, true):
                return .trailing
            default:
                return .leading
            }
        }

        return alignments.count == expectedCount ? alignments : nil
    }
}
