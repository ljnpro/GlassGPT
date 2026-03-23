import ChatDomain
import Foundation

public extension OpenAIService {
    /// Starts a streaming chat completion, cancelling any active stream first.
    /// - Parameters:
    ///   - apiKey: The API key for authentication.
    ///   - messages: The conversation message history.
    ///   - model: The model to use.
    ///   - reasoningEffort: The reasoning effort level.
    ///   - backgroundModeEnabled: Whether background mode is enabled.
    ///   - serviceTier: The service tier for the request.
    ///   - vectorStoreIds: Optional vector store IDs for file search.
    /// - Returns: An async stream of ``StreamEvent`` values.
    func streamChat(
        apiKey: String,
        messages: [APIMessage],
        model: ModelType,
        reasoningEffort: ReasoningEffort,
        backgroundModeEnabled: Bool,
        serviceTier: ServiceTier,
        vectorStoreIds: [String] = []
    ) -> AsyncStream<StreamEvent> {
        cancelStream()

        let primaryRequest: URLRequest
        let fallbackRequest: URLRequest?
        do {
            primaryRequest = try requestBuilder.streamingRequest(
                apiKey: apiKey,
                messages: messages,
                model: model,
                reasoningEffort: reasoningEffort,
                backgroundModeEnabled: backgroundModeEnabled,
                serviceTier: serviceTier,
                vectorStoreIds: vectorStoreIds
            )
            if requestBuilder.configuration.usesGatewayRouting {
                fallbackRequest = try requestBuilder.streamingRequest(
                    apiKey: apiKey,
                    messages: messages,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    backgroundModeEnabled: backgroundModeEnabled,
                    serviceTier: serviceTier,
                    vectorStoreIds: vectorStoreIds,
                    useDirectBaseURL: true
                )
            } else {
                fallbackRequest = nil
            }
        } catch {
            return AsyncStream { continuation in
                continuation.yield(.error(.requestFailed("Failed to encode request")))
                continuation.finish()
            }
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(256)) { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await forwardChatStream(
                    primaryRequest: primaryRequest,
                    fallbackRequest: fallbackRequest,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { @MainActor [weak self] in
                    self?.cancelStream()
                }
            }
        }
    }
}

private extension OpenAIService {
    func forwardChatStream(
        primaryRequest: URLRequest,
        fallbackRequest: URLRequest?,
        continuation: AsyncStream<StreamEvent>.Continuation
    ) async {
        let shouldRetryDirect = await relayStream(
            request: primaryRequest,
            continuation: continuation,
            suppressInitialFailure: fallbackRequest != nil
        )

        guard !Task.isCancelled else {
            continuation.finish()
            return
        }

        if shouldRetryDirect, let fallbackRequest {
            cancelStream()
            _ = await relayStream(
                request: fallbackRequest,
                continuation: continuation,
                suppressInitialFailure: false
            )
        }

        continuation.finish()
    }

    func relayStream(
        request: URLRequest,
        continuation: AsyncStream<StreamEvent>.Continuation,
        suppressInitialFailure: Bool
    ) async -> Bool {
        var sawMeaningfulProgress = false

        for await event in streamClient.makeStream(request: request) {
            guard !Task.isCancelled else {
                return false
            }

            switch event {
            case .error, .connectionLost:
                if suppressInitialFailure, !sawMeaningfulProgress {
                    return true
                }
                continuation.yield(event)
            default:
                sawMeaningfulProgress = true
                continuation.yield(event)
            }
        }

        return false
    }
}
