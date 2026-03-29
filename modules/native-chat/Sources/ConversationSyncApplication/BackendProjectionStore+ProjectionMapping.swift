import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatProjectionPersistence
import Foundation
import SyncProjection

@MainActor
extension BackendProjectionStore {
    func ensureConversation(
        for event: RunEventDTO,
        accountID: String
    ) throws(PersistenceError) -> Conversation {
        if let cached = try cacheRepository.fetchConversation(
            serverID: event.conversationID,
            accountID: accountID
        ) {
            return cached
        }

        let fallbackConversation = event.conversation ?? ConversationDTO(
            id: event.conversationID,
            title: "Conversation",
            mode: event.run?.kind == .agent ? .agent : .chat,
            createdAt: event.createdAt,
            updatedAt: event.createdAt,
            lastRunID: event.runID,
            lastSyncCursor: event.cursor,
            model: nil,
            reasoningEffort: nil,
            agentWorkerReasoningEffort: nil,
            serviceTier: nil
        )
        return try cacheRepository.upsertConversation(
            conversationRecord(from: fallbackConversation, accountID: accountID)
        )
    }

    func conversationRecord(
        from conversation: ConversationDTO,
        accountID: String
    ) -> ConversationProjectionRecord {
        ConversationProjectionRecord(
            serverID: conversation.id,
            accountID: accountID,
            title: conversation.title,
            mode: conversation.mode == .agent ? .agent : .chat,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            lastRunServerID: conversation.lastRunID,
            lastSyncCursor: conversation.lastSyncCursor,
            model: conversation.model?.rawValue,
            reasoningEffort: conversation.reasoningEffort?.rawValue,
            agentWorkerReasoningEffort: conversation.agentWorkerReasoningEffort?.rawValue,
            serviceTier: conversation.serviceTier?.rawValue
        )
    }

    func messageRecord(
        from message: MessageDTO,
        accountID: String
    ) -> MessageProjectionRecord {
        MessageProjectionRecord(
            serverID: message.id,
            accountID: accountID,
            role: messageRole(from: message.role),
            content: message.content,
            thinking: message.thinking,
            createdAt: message.createdAt,
            completedAt: message.completedAt,
            serverCursor: message.serverCursor,
            serverRunID: message.runID,
            annotations: (message.annotations ?? []).map(urlCitation(from:)),
            toolCalls: (message.toolCalls ?? []).map(toolCall(from:)),
            filePathAnnotations: (message.filePathAnnotations ?? []).map(filePathAnnotation(from:)),
            agentTrace: agentTrace(fromJSON: message.agentTraceJSON)
        )
    }

    func messageRole(from role: MessageRoleDTO) -> MessageRole {
        switch role {
        case .system:
            .system
        case .user:
            .user
        case .assistant:
            .assistant
        case .tool:
            .tool
        }
    }

    func toolCall(from toolCall: ToolCallInfoDTO) -> ToolCallInfo {
        let type: ToolCallType = switch toolCall.type {
        case .webSearch:
            .webSearch
        case .codeInterpreter:
            .codeInterpreter
        case .fileSearch:
            .fileSearch
        }

        let status: ToolCallStatus = switch toolCall.status {
        case .inProgress:
            .inProgress
        case .searching:
            .searching
        case .interpreting:
            .interpreting
        case .fileSearching:
            .fileSearching
        case .completed:
            .completed
        }

        return ToolCallInfo(
            id: toolCall.id,
            type: type,
            status: status,
            code: toolCall.code,
            results: toolCall.results,
            queries: toolCall.queries
        )
    }

    func urlCitation(from citation: URLCitationDTO) -> URLCitation {
        URLCitation(
            url: citation.url,
            title: citation.title,
            startIndex: citation.startIndex,
            endIndex: citation.endIndex
        )
    }

    func filePathAnnotation(from annotation: FilePathAnnotationDTO) -> FilePathAnnotation {
        FilePathAnnotation(
            fileId: annotation.fileId,
            containerId: annotation.containerId,
            sandboxPath: annotation.sandboxPath,
            filename: annotation.filename,
            startIndex: annotation.startIndex,
            endIndex: annotation.endIndex
        )
    }

    func agentTrace(fromJSON json: String?) -> AgentTurnTrace? {
        guard let json, let data = json.data(using: .utf8) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AgentTurnTrace.self, from: data)
        } catch {
            return nil
        }
    }

    func filterEvents(
        _ events: [RunEventDTO],
        after cursor: SyncCursor?
    ) throws(PersistenceError) -> [RunEventDTO] {
        var lastCursor = cursor
        var filtered: [RunEventDTO] = []

        for event in events {
            let eventCursor = SyncCursor(rawValue: event.cursor)
            if let cursor, eventCursor <= cursor {
                continue
            }
            if let lastCursor, eventCursor <= lastCursor {
                throw .migrationFailure(
                    underlying: RunEventProjectionError.eventCursorOutOfOrder(
                        previous: lastCursor,
                        current: eventCursor
                    )
                )
            }
            filtered.append(event)
            lastCursor = eventCursor
        }

        return filtered
    }
}
