import ChatDomain
import Foundation

enum AgentTaggedOutputParser {
    enum LeaderDecision: String, Equatable {
        case delegate
        case finish
        case clarify
    }

    struct LeaderDirective: Equatable {
        let focus: String
        let decision: LeaderDecision
        let plan: [AgentPlanStep]
        let tasks: [AgentTask]
        let decisionNote: String
        let stopReason: String?
    }

    struct WorkerRevision: Equatable {
        let summary: String
        let adoptedPoints: [String]
    }

    struct WorkerTaskResult: Equatable {
        let summary: String
        let evidence: [String]
        let confidence: AgentConfidence
        let risks: [String]
        let followUps: [AgentTaskSuggestion]
    }

    static func parseLeaderDirective(from text: String) -> LeaderDirective {
        let focus = parseSection("FOCUS", in: text) ?? fallbackText(from: text)
        let decision = LeaderDecision(
            rawValue: (parseSection("DECISION", in: text) ?? "finish")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .finish
        let planLines = parseLines(in: "PLAN", text: text)
        let taskLines = parseLines(in: "TASKS", text: text)
        let plan = planLines.compactMap(parsePlanStep)
        let tasks = taskLines.compactMap(parseTask)
        let decisionNote = parseSection("DECISION_NOTE", in: text) ?? ""
        let stopReason = parseSection("STOP_REASON", in: text)

        return LeaderDirective(
            focus: focus,
            decision: decision,
            plan: plan,
            tasks: tasks,
            decisionNote: decisionNote,
            stopReason: stopReason
        )
    }

    static func parseLeaderBrief(from text: String) -> String {
        parseSection("BRIEF", in: text)
            ?? parseSection("FOCUS", in: text)
            ?? fallbackText(from: text)
    }

    static func parseWorkerSummary(from text: String) -> String {
        parseSection("SUMMARY", in: text) ?? fallbackText(from: text)
    }

    static func parseWorkerRevision(from text: String) -> WorkerRevision {
        let summary = parseSection("SUMMARY", in: text) ?? fallbackText(from: text)
        let adoptedBlock = parseSection("ADOPTED", in: text) ?? ""
        let adoptedPoints = listItems(from: adoptedBlock)
        return WorkerRevision(summary: summary, adoptedPoints: adoptedPoints)
    }

    static func parseWorkerTaskResult(from text: String) -> WorkerTaskResult {
        let summary = parseSection("SUMMARY", in: text) ?? fallbackText(from: text)
        let evidence = listItems(from: parseSection("EVIDENCE", in: text) ?? "")
        let risks = listItems(from: parseSection("RISKS", in: text) ?? "")
        let confidence = AgentConfidence(
            rawValue: (parseSection("CONFIDENCE", in: text) ?? "medium")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        ) ?? .medium
        let followUps = parseLines(in: "FOLLOW_UP", text: text).compactMap(parseSuggestion)
        return WorkerTaskResult(
            summary: summary,
            evidence: evidence,
            confidence: confidence,
            risks: risks,
            followUps: followUps
        )
    }

    private static func parsePlanStep(from line: String) -> AgentPlanStep? {
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

    private static func parseTask(from line: String) -> AgentTask? {
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

    private static func parseSuggestion(from line: String) -> AgentTaskSuggestion? {
        let parts = split(line)
        guard parts.count >= 3 else { return nil }
        return AgentTaskSuggestion(
            title: parts[0],
            goal: parts[1],
            toolPolicy: AgentToolPolicy(rawValue: parts[2]) ?? .enabled
        )
    }

    private static func parseLines(in name: String, text: String) -> [String] {
        let block = parseSection(name, in: text) ?? ""
        return block
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func split(_ line: String) -> [String] {
        line.components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func listItems(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.hasPrefix("-") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
            .filter { !$0.isEmpty }
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
            .replacingOccurrences(of: "[FOCUS]", with: "")
            .replacingOccurrences(of: "[/FOCUS]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
