import ChatDomain
import Foundation

extension AgentTaggedOutputParser {
    static func parsePlanStep(from line: String) -> AgentPlanStep? {
        let parts = split(line)
        guard parts.count >= 6 else { return nil }
        let owner = AgentTaskOwner(rawValue: parts[2]) ?? .leader
        let status = AgentPlanStepStatus(rawValue: parts[3]) ?? .planned
        let parentID = parts[1] == "root" ? nil : parts[1]
        return AgentPlanStep(
            id: parts[0],
            parentStepID: parentID,
            owner: owner,
            status: status,
            title: parts[4],
            summary: parts[5]
        )
    }

    static func parseTask(from line: String) -> AgentTask? {
        let parts = split(line)
        guard parts.count >= 6,
              let owner = AgentTaskOwner(rawValue: parts[0]),
              owner != .leader
        else {
            return nil
        }
        let toolPolicy = AgentToolPolicy(rawValue: parts[2]) ?? .enabled
        let parentStepID = parts[1] == "root" ? nil : parts[1]
        return AgentTask(
            owner: owner,
            parentStepID: parentStepID,
            title: parts[3],
            goal: parts[4],
            expectedOutput: parts[5],
            contextSummary: parts[4],
            toolPolicy: toolPolicy
        )
    }

    static func parseSuggestion(from line: String) -> AgentTaskSuggestion? {
        let parts = split(line)
        guard parts.count >= 3 else { return nil }
        return AgentTaskSuggestion(
            title: parts[0],
            goal: parts[1],
            toolPolicy: AgentToolPolicy(rawValue: parts[2]) ?? .enabled
        )
    }

    static func parseLines(
        in name: String,
        text: String,
        allowPartial: Bool = false
    ) -> [String] {
        let block = parseSection(name, in: text, allowPartial: allowPartial) ?? ""
        return block
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func split(_ line: String) -> [String] {
        line.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func listItems(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("-") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
    }

    static func parseSection(
        _ name: String,
        in text: String,
        allowPartial: Bool = false
    ) -> String? {
        let startTag = "[\(name)]"
        let endTag = "[/\(name)]"
        guard let startRange = text.range(of: startTag) else {
            return nil
        }

        let bodyRange: Range<String.Index>
        if let endRange = text.range(of: endTag) {
            bodyRange = startRange.upperBound ..< endRange.lowerBound
        } else if allowPartial {
            let trailingText = text[startRange.upperBound...]
            if let nextTagRange = trailingText.range(of: "\n[") {
                bodyRange = startRange.upperBound ..< nextTagRange.lowerBound
            } else {
                bodyRange = startRange.upperBound ..< text.endIndex
            }
        } else {
            return nil
        }

        let body = text[bodyRange]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    static func fallbackText(from text: String) -> String {
        text
            .replacingOccurrences(of: "[SUMMARY]", with: "")
            .replacingOccurrences(of: "[/SUMMARY]", with: "")
            .replacingOccurrences(of: "[BRIEF]", with: "")
            .replacingOccurrences(of: "[/BRIEF]", with: "")
            .replacingOccurrences(of: "[FOCUS]", with: "")
            .replacingOccurrences(of: "[/FOCUS]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
