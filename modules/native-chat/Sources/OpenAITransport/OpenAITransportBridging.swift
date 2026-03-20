import AITransportContracts
import ChatDomain

/// Bridges ``OpenAIServiceError`` to the provider-agnostic ``AIServiceError``.
extension OpenAIServiceError {
    /// Converts this OpenAI-specific error to a provider-agnostic error.
    public var asAIServiceError: AIServiceError {
        switch self {
        case .noAPIKey:
            .noCredentials
        case .invalidURL:
            .invalidEndpoint
        case let .httpError(code, message):
            .httpError(code, message)
        case let .requestFailed(message):
            .requestFailed(message)
        case .cancelled:
            .cancelled
        }
    }
}

/// Bridges ``StreamEvent`` to the provider-agnostic ``AIStreamEvent``.
extension StreamEvent {
    /// Converts this OpenAI-specific stream event to a provider-agnostic event.
    public var asAIStreamEvent: AIStreamEvent {
        switch self {
        case let .textDelta(text):
            .textDelta(text)
        case let .thinkingDelta(text):
            .thinkingDelta(text)
        case .thinkingStarted:
            .thinkingStarted
        case .thinkingFinished:
            .thinkingFinished
        case let .responseCreated(id):
            .responseCreated(id)
        case let .sequenceUpdate(seq):
            .sequenceUpdate(seq)
        case let .completed(text, thinking, fileAnnotations):
            .completed(text, thinking, fileAnnotations)
        case let .incomplete(text, thinking, fileAnnotations, message):
            .incomplete(text, thinking, fileAnnotations, message)
        case .connectionLost:
            .connectionLost
        case let .error(error):
            .error(error.asAIServiceError)
        case let .webSearchStarted(id):
            .webSearchStarted(id)
        case let .webSearchSearching(id):
            .webSearchSearching(id)
        case let .webSearchCompleted(id):
            .webSearchCompleted(id)
        case let .codeInterpreterStarted(id):
            .codeInterpreterStarted(id)
        case let .codeInterpreterInterpreting(id):
            .codeInterpreterInterpreting(id)
        case let .codeInterpreterCodeDelta(id, code):
            .codeInterpreterCodeDelta(id, code)
        case let .codeInterpreterCodeDone(id, code):
            .codeInterpreterCodeDone(id, code)
        case let .codeInterpreterCompleted(id):
            .codeInterpreterCompleted(id)
        case let .fileSearchStarted(id):
            .fileSearchStarted(id)
        case let .fileSearchSearching(id):
            .fileSearchSearching(id)
        case let .fileSearchCompleted(id):
            .fileSearchCompleted(id)
        case let .annotationAdded(citation):
            .annotationAdded(citation)
        case let .filePathAnnotationAdded(annotation):
            .filePathAnnotationAdded(annotation)
        }
    }
}

/// Bridges ``OpenAIResponseFetchResult`` to the provider-agnostic ``AIResponseFetchResult``.
extension OpenAIResponseFetchResult {
    /// Converts this OpenAI-specific fetch result to a provider-agnostic result.
    public var asAIResponseFetchResult: AIResponseFetchResult {
        AIResponseFetchResult(
            status: status.asAIStatus,
            text: text,
            thinking: thinking,
            annotations: annotations,
            toolCalls: toolCalls,
            filePathAnnotations: filePathAnnotations,
            errorMessage: errorMessage
        )
    }
}

/// Bridges ``OpenAIResponseFetchResult.Status`` to ``AIResponseFetchResult.Status``.
extension OpenAIResponseFetchResult.Status {
    /// Converts this OpenAI-specific status to a provider-agnostic status.
    public var asAIStatus: AIResponseFetchResult.Status {
        switch self {
        case .queued: .queued
        case .inProgress: .inProgress
        case .completed: .completed
        case .failed: .failed
        case .incomplete: .incomplete
        case .unknown: .unknown
        }
    }
}
