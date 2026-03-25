import ChatDomain
import Foundation

enum AgentTaggedOutputParser {
    struct WorkerRevision: Equatable {
        let summary: String
        let adoptedPoints: [String]
    }

    static func parseLeaderBrief(from text: String) -> String {
        parseSection("BRIEF", in: text) ?? fallbackText(from: text)
    }

    static func parseWorkerSummary(from text: String) -> String {
        parseSection("SUMMARY", in: text) ?? fallbackText(from: text)
    }

    static func parseWorkerRevision(from text: String) -> WorkerRevision {
        let summary = parseSection("SUMMARY", in: text) ?? fallbackText(from: text)
        let adoptedBlock = parseSection("ADOPTED", in: text) ?? ""
        let adoptedPoints = adoptedBlock
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("-") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
        return WorkerRevision(summary: summary, adoptedPoints: adoptedPoints)
    }

    private static func parseSection(_ name: String, in text: String) -> String? {
        let startTag = "[\(name)]"
        let endTag = "[/\(name)]"
        guard
            let startRange = text.range(of: startTag),
            let endRange = text.range(of: endTag)
        else {
            return nil
        }

        let body = text[startRange.upperBound ..< endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private static func fallbackText(from text: String) -> String {
        text
            .replacingOccurrences(of: "[SUMMARY]", with: "")
            .replacingOccurrences(of: "[/SUMMARY]", with: "")
            .replacingOccurrences(of: "[BRIEF]", with: "")
            .replacingOccurrences(of: "[/BRIEF]", with: "")
            .replacingOccurrences(of: "[ADOPTED]", with: "")
            .replacingOccurrences(of: "[/ADOPTED]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
