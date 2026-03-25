import ChatDomain
import Foundation

enum AgentSummaryFormatter {
    static func summarize(
        _ text: String,
        maxLength: Int = 220
    ) -> String {
        let normalized = normalizedText(text)
        guard normalized.count > maxLength else {
            return normalized
        }

        let cutoffIndex = normalized.index(normalized.startIndex, offsetBy: maxLength)
        let prefix = String(normalized[..<cutoffIndex])
        let trimmed = prefix.replacingOccurrences(
            of: #"\s+\S*$"#,
            with: "",
            options: .regularExpression
        )
        let resolved = trimmed.isEmpty ? prefix : trimmed
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func summarizeBullets(
        _ items: [String],
        maxItems: Int = 2,
        maxLength: Int = 120
    ) -> [String] {
        items
            .map { summarize($0, maxLength: maxLength) }
            .filter { !$0.isEmpty }
            .prefix(maxItems)
            .map(\.self)
    }

    static func latestCompletedWorkerTask(
        role: AgentRole,
        from snapshot: AgentProcessSnapshot
    ) -> AgentTask? {
        snapshot.tasks
            .filter { $0.owner.role == role && $0.status == .completed }
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? lhs.startedAt ?? .distantPast
                let rhsDate = rhs.completedAt ?? rhs.startedAt ?? .distantPast
                return lhsDate < rhsDate
            }
            .last
    }

    static func workerSummaries(from snapshot: AgentProcessSnapshot) -> [AgentWorkerSummary] {
        [AgentRole.workerA, .workerB, .workerC].compactMap { role in
            guard let task = latestCompletedWorkerTask(role: role, from: snapshot) else {
                return nil
            }
            return AgentWorkerSummary(
                role: role,
                summary: summarize(task.result?.summary ?? task.resultSummary ?? task.title, maxLength: 260),
                adoptedPoints: summarizeBullets(task.result?.evidence ?? [])
            )
        }
    }

    static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
