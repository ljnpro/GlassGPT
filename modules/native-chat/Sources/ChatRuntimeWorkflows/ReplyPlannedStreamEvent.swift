import ChatDomain
import Foundation
import OpenAITransport

enum ReplyPlannedStreamEvent {
    case content(ReplyContentStreamEvent)
    case tool(ReplyToolStreamEvent)
    case annotation(ReplyAnnotationStreamEvent)
    case terminal(ReplyTerminalStreamEvent)

    init(_ event: StreamEvent) {
        if let content = Self.contentEvent(from: event) {
            self = .content(content)
            return
        }
        if let webSearch = Self.webSearchEvent(from: event) {
            self = .tool(.webSearch(webSearch))
            return
        }
        if let codeInterpreter = Self.codeInterpreterEvent(from: event) {
            self = .tool(.codeInterpreter(codeInterpreter))
            return
        }
        if let fileSearch = Self.fileSearchEvent(from: event) {
            self = .tool(.fileSearch(fileSearch))
            return
        }
        if let annotation = Self.annotationEvent(from: event) {
            self = .annotation(annotation)
            return
        }

        self = .terminal(Self.terminalEvent(from: event))
    }

    private static func contentEvent(from event: StreamEvent) -> ReplyContentStreamEvent? {
        switch event {
        case let .responseCreated(responseID):
            .responseCreated(responseID)
        case let .sequenceUpdate(sequence):
            .sequenceUpdate(sequence)
        case let .textDelta(delta):
            .textDelta(delta)
        case let .thinkingDelta(delta):
            .thinkingDelta(delta)
        case .thinkingStarted:
            .thinkingStarted
        case .thinkingFinished:
            .thinkingFinished
        default:
            nil
        }
    }

    private static func webSearchEvent(from event: StreamEvent) -> ReplyWebSearchStreamEvent? {
        switch event {
        case let .webSearchStarted(callID):
            .started(callID)
        case let .webSearchSearching(callID):
            .searching(callID)
        case let .webSearchCompleted(callID):
            .completed(callID)
        default:
            nil
        }
    }

    private static func codeInterpreterEvent(from event: StreamEvent) -> ReplyCodeInterpreterStreamEvent? {
        switch event {
        case let .codeInterpreterStarted(callID):
            .started(callID)
        case let .codeInterpreterInterpreting(callID):
            .interpreting(callID)
        case let .codeInterpreterCodeDelta(callID, codeDelta):
            .codeDelta(callID, codeDelta)
        case let .codeInterpreterCodeDone(callID, fullCode):
            .codeDone(callID, fullCode)
        case let .codeInterpreterCompleted(callID):
            .completed(callID)
        default:
            nil
        }
    }

    private static func fileSearchEvent(from event: StreamEvent) -> ReplyFileSearchStreamEvent? {
        switch event {
        case let .fileSearchStarted(callID):
            .started(callID)
        case let .fileSearchSearching(callID):
            .searching(callID)
        case let .fileSearchCompleted(callID):
            .completed(callID)
        default:
            nil
        }
    }

    private static func annotationEvent(from event: StreamEvent) -> ReplyAnnotationStreamEvent? {
        switch event {
        case let .annotationAdded(citation):
            .citation(citation)
        case let .filePathAnnotationAdded(annotation):
            .filePath(annotation)
        default:
            nil
        }
    }

    private static func terminalEvent(from event: StreamEvent) -> ReplyTerminalStreamEvent {
        switch event {
        case let .completed(text, thinking, filePathAnnotations):
            .completed(text, thinking, filePathAnnotations)
        case let .incomplete(text, thinking, filePathAnnotations, message):
            .incomplete(text, thinking, filePathAnnotations, message)
        case .connectionLost:
            .connectionLost
        case let .error(error):
            .error(error)
        default:
            .connectionLost
        }
    }
}

enum ReplyContentStreamEvent {
    case responseCreated(String)
    case sequenceUpdate(Int)
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingStarted
    case thinkingFinished
}

enum ReplyToolStreamEvent {
    case webSearch(ReplyWebSearchStreamEvent)
    case codeInterpreter(ReplyCodeInterpreterStreamEvent)
    case fileSearch(ReplyFileSearchStreamEvent)
}

enum ReplyWebSearchStreamEvent {
    case started(String)
    case searching(String)
    case completed(String)
}

enum ReplyCodeInterpreterStreamEvent {
    case started(String)
    case interpreting(String)
    case codeDelta(String, String)
    case codeDone(String, String)
    case completed(String)
}

enum ReplyFileSearchStreamEvent {
    case started(String)
    case searching(String)
    case completed(String)
}

enum ReplyAnnotationStreamEvent {
    case citation(URLCitation)
    case filePath(FilePathAnnotation)
}

enum ReplyTerminalStreamEvent {
    case completed(String, String?, [FilePathAnnotation]?)
    case incomplete(String, String?, [FilePathAnnotation]?, String?)
    case connectionLost
    case error(OpenAIServiceError)
}
