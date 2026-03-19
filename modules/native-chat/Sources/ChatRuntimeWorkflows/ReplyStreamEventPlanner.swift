import Foundation
import OpenAITransport

/// Maps transport stream events onto runtime-owned transitions and persistence intent.
public enum ReplyStreamEventPlanner {
    /// Creates a runtime plan for the given transport event.
    /// - Parameters:
    ///   - event: The incoming transport event.
    ///   - context: Runtime context needed to preserve semantics.
    /// - Returns: The stream event plan.
    public static func plan(
        _ event: StreamEvent,
        context: ReplyStreamEventContext
    ) -> ReplyStreamEventPlan {
        switch ReplyPlannedStreamEvent(event) {
        case let .content(event):
            contentPlan(for: event, context: context)
        case let .tool(event):
            toolPlan(for: event)
        case let .annotation(event):
            annotationPlan(for: event)
        case let .terminal(event):
            terminalPlan(for: event)
        }
    }

    private static func annotationPlan(for event: ReplyAnnotationStreamEvent) -> ReplyStreamEventPlan {
        switch event {
        case let .citation(citation):
            ReplyStreamEventPlan(
                transition: .addCitation(citation),
                projection: .animated(.activityUpdated),
                persistence: .saveIfNeeded,
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        case let .filePath(annotation):
            ReplyStreamEventPlan(
                transition: .addFilePathAnnotation(annotation),
                projection: .animated(.activityUpdated),
                persistence: .saveIfNeeded,
                responseMetadataUpdate: nil,
                outcome: .continued
            )
        }
    }

    private static func terminalPlan(for event: ReplyTerminalStreamEvent) -> ReplyStreamEventPlan {
        switch event {
        case let .completed(fullText, fullThinking, filePathAnnotations):
            ReplyStreamEventPlan(
                transition: .mergeTerminalPayload(
                    text: fullText,
                    thinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                ),
                projection: .none,
                persistence: .saveNow,
                responseMetadataUpdate: nil,
                outcome: .terminalCompleted
            )
        case let .incomplete(fullText, fullThinking, filePathAnnotations, message):
            ReplyStreamEventPlan(
                transition: .mergeTerminalPayload(
                    text: fullText,
                    thinking: fullThinking,
                    filePathAnnotations: filePathAnnotations
                ),
                projection: .none,
                persistence: .saveNow,
                responseMetadataUpdate: nil,
                outcome: .terminalIncomplete(message)
            )
        case .connectionLost:
            ReplyStreamEventPlan(
                transition: nil,
                projection: .none,
                persistence: .none,
                responseMetadataUpdate: nil,
                outcome: .connectionLost
            )
        case let .error(error):
            ReplyStreamEventPlan(
                transition: nil,
                projection: .none,
                persistence: .none,
                responseMetadataUpdate: nil,
                outcome: .terminalFailure(error.localizedDescription)
            )
        }
    }
}
