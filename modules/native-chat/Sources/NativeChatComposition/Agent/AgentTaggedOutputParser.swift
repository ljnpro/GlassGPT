import ChatDomain
import Foundation

enum AgentTaggedOutputParser {
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

    static func parseLeaderDirectivePreview(from text: String) -> LeaderDirectivePreview {
        let plan = parseLines(in: "PLAN", text: text, allowPartial: true).compactMap(parsePlanStep)
        let tasks = parseLines(in: "TASKS", text: text, allowPartial: true).compactMap(parseTask)
        return LeaderDirectivePreview(
            status: parseSection("STATUS", in: text, allowPartial: true),
            focus: parseSection("FOCUS", in: text, allowPartial: true),
            decisionNote: parseSection("DECISION_NOTE", in: text, allowPartial: true),
            plan: plan,
            tasks: tasks
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

    static func parseWorkerTaskPreview(from text: String) -> WorkerTaskPreview {
        let confidenceText = parseSection("CONFIDENCE", in: text, allowPartial: true)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return WorkerTaskPreview(
            status: parseSection("STATUS", in: text, allowPartial: true),
            summary: parseSection("SUMMARY", in: text, allowPartial: true),
            evidence: listItems(from: parseSection("EVIDENCE", in: text, allowPartial: true) ?? ""),
            confidence: confidenceText.flatMap(AgentConfidence.init(rawValue:)),
            risks: listItems(from: parseSection("RISKS", in: text, allowPartial: true) ?? "")
        )
    }
}
