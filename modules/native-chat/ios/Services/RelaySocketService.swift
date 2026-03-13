import Foundation
import SocketIO

private struct ActiveRelaySubscription {
    var relayRunId: String
    var resumeToken: String
    var responseId: String?
    var apiKey: String
    var lastSequenceNumber: Int

    var joinPayload: JSONDictionary {
        var payload: JSONDictionary = [
            "relayRunId": relayRunId,
            "resumeToken": resumeToken
        ]

        if lastSequenceNumber > 0 {
            payload["lastSequenceNumber"] = lastSequenceNumber
        }

        if let responseId, !responseId.isEmpty {
            payload["responseId"] = responseId
        }

        return payload
    }

    var resumePayload: JSONDictionary? {
        guard let responseId, !responseId.isEmpty else { return nil }

        var payload: JSONDictionary = [
            "relayRunId": relayRunId,
            "resumeToken": resumeToken,
            "responseId": responseId,
            "apiKey": apiKey
        ]

        if lastSequenceNumber > 0 {
            payload["lastSequenceNumber"] = lastSequenceNumber
        }

        return payload
    }
}

final class RelaySocketService: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.liquidglasschat.relay.socket")
    private let lock = NSLock()

    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var continuation: AsyncStream<StreamEvent>.Continuation?
    private var activeSubscription: ActiveRelaySubscription?

    private var suppressDisconnectEvents = false
    private var didYieldTerminalEvent = false
    private var thinkingActive = false
    private var accumulatedText = ""
    private var accumulatedThinking = ""
    private var latestErrorMessage: String?

    private var _lastDeliveredEventWasReplay = false
    private var _currentLastSequenceNumber = 0

    var lastDeliveredEventWasReplay: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _lastDeliveredEventWasReplay
    }

    var currentLastSequenceNumber: Int {
        lock.lock()
        defer { lock.unlock() }
        return _currentLastSequenceNumber
    }

    func streamRun(
        relayRunId: String,
        resumeToken: String,
        responseId: String?,
        apiKey: String,
        lastSequenceNumber: Int = 0
    ) -> AsyncStream<StreamEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            self.queue.async {
                self.finishContinuation()
                self.resetPerStreamState()
                self.continuation = continuation
                self.activeSubscription = ActiveRelaySubscription(
                    relayRunId: relayRunId,
                    resumeToken: resumeToken,
                    responseId: responseId,
                    apiKey: apiKey,
                    lastSequenceNumber: max(0, lastSequenceNumber)
                )
                self.setDeliveryState(replay: false, sequenceNumber: max(0, lastSequenceNumber))

                do {
                    try self.configureSocketIfNeeded()
                    self.performWhenConnected { [weak self] in
                        self?.requestJoinForActiveRun()
                    }
                } catch {
                    continuation.yield(.error(.requestFailed(error.localizedDescription)))
                    continuation.finish()
                    self.continuation = nil
                }
            }

            continuation.onTermination = { @Sendable _ in
                self.queue.async {
                    self.continuation = nil
                }
            }
        }
    }

    func rejoinRun(
        relayRunId: String,
        resumeToken: String,
        responseId: String?,
        apiKey: String,
        lastSequenceNumber: Int = 0
    ) {
        queue.async {
            self.activeSubscription = ActiveRelaySubscription(
                relayRunId: relayRunId,
                resumeToken: resumeToken,
                responseId: responseId,
                apiKey: apiKey,
                lastSequenceNumber: max(0, lastSequenceNumber)
            )

            do {
                try self.configureSocketIfNeeded()
                self.performWhenConnected { [weak self] in
                    self?.requestJoinForActiveRun()
                }
            } catch {
                self.continuation?.yield(.error(.requestFailed(error.localizedDescription)))
                self.finishContinuation()
            }
        }
    }

    func cancelRun(
        relayRunId: String,
        resumeToken: String,
        apiKey: String
    ) async throws -> RelayCancelResponse {
        try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                do {
                    try self.configureSocketIfNeeded()

                    self.performWhenConnected { [weak self] in
                        guard let self else { return }

                        let payload: JSONDictionary = [
                            "relayRunId": relayRunId,
                            "resumeToken": resumeToken,
                            "apiKey": apiKey
                        ]

                        self.emitWithAck(
                            event: "relay:cancel",
                            payload: payload,
                            timeout: 10
                        ) { result in
                            switch result {
                            case .success(let ack):
                                guard
                                    let ok = ack.bool("ok"),
                                    let returnedRelayRunId = ack.string("relayRunId"),
                                    let statusRaw = ack.string("status"),
                                    let status = RelayRunStatus(rawValue: statusRaw)
                                else {
                                    continuation.resume(throwing: RelayAPIServiceError.decodeFailure("Invalid relay cancel ack."))
                                    return
                                }

                                continuation.resume(
                                    returning: RelayCancelResponse(
                                        ok: ok,
                                        relayRunId: returnedRelayRunId,
                                        status: status,
                                        responseId: ack.string("responseId")
                                    )
                                )

                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func leaveRun(relayRunId: String) {
        queue.async {
            guard let socket = self.socket else { return }
            socket.emit("relay:leave", ["relayRunId": relayRunId])
        }
    }

    func reset() {
        queue.async {
            self.resetLocked()
        }
    }

    private func configureSocketIfNeeded() throws {
        let baseURL = try RelayAPIService.configuredBaseURL()

        if let manager, let socket, manager.socketURL == baseURL {
            self.manager = manager
            self.socket = socket
            return
        }

        resetLocked()

        let manager = SocketManager(
            socketURL: baseURL,
            config: [
                .path(RELAY_SOCKET_PATH),
                .forceWebsockets(true),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWait(1),
                .reconnectWaitMax(5),
                .randomizationFactor(0.5),
                .handleQueue(queue),
                .log(false)
            ]
        )

        let socket = manager.defaultSocket
        self.manager = manager
        self.socket = socket
        installHandlers(on: socket)
    }

    private func installHandlers(on socket: SocketIOClient) {
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self else { return }
            self.suppressDisconnectEvents = false
            self.requestJoinForActiveRun()
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self else { return }
            if self.suppressDisconnectEvents {
                return
            }
            self.continuation?.yield(.connectionLost)
        }

        socket.on(clientEvent: .error) { [weak self] data, _ in
            guard let self else { return }

            if let message = Self.firstString(from: data), !message.isEmpty {
                self.latestErrorMessage = message
            }

            self.continuation?.yield(.connectionLost)
        }

        socket.on("relay:joined") { [weak self] data, _ in
            guard let self else { return }
            guard let payload = Self.firstDictionary(from: data) else { return }

            if let responseId = payload.string("responseId"), !responseId.isEmpty {
                self.updateActiveResponseId(responseId)
            }
        }

        socket.on("relay:event") { [weak self] data, _ in
            guard let self else { return }
            guard let payload = Self.firstDictionary(from: data) else { return }
            self.handleRelayEventEnvelope(payload)
        }

        socket.on("relay:live") { [weak self] _, _ in
            guard let self else { return }
            self.setReplayFlag(false)
        }

        socket.on("relay:done") { [weak self] data, _ in
            guard let self else { return }
            guard let payload = Self.firstDictionary(from: data) else { return }
            self.handleRelayDone(payload)
        }

        socket.on("relay:error") { [weak self] data, _ in
            guard let self else { return }
            guard let payload = Self.firstDictionary(from: data) else { return }
            self.handleRelayError(payload)
        }
    }

    private func performWhenConnected(_ work: @escaping () -> Void) {
        guard let socket else { return }

        switch socket.status {
        case .connected:
            work()

        case .connecting:
            socket.once(clientEvent: .connect) { _, _ in
                work()
            }

        case .notConnected, .disconnected:
            socket.once(clientEvent: .connect) { _, _ in
                work()
            }
            socket.connect()
        }
    }

    private func requestJoinForActiveRun() {
        guard let active = activeSubscription else { return }

        emitWithAck(
            event: "relay:join",
            payload: active.joinPayload,
            timeout: 10
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let ack):
                let ok = ack.bool("ok") ?? false
                if ok {
                    return
                }

                let code = ack.string("code") ?? "internal_error"
                let message = ack.string("message") ?? "Failed to join relay run."
                let retryable = ack.bool("retryable") ?? false
                self.handleAckError(code: code, message: message, retryable: retryable)

            case .failure(let error):
                self.latestErrorMessage = error.localizedDescription
                self.continuation?.yield(.connectionLost)
            }
        }
    }

    private func requestResumeOpenAIForActiveRun() {
        guard let active = activeSubscription, let payload = active.resumePayload else {
            let message = latestErrorMessage ?? "Relay cache miss and no response ID available for upstream resume."
            continuation?.yield(.error(.requestFailed(message)))
            finishContinuation()
            return
        }

        emitWithAck(
            event: "relay:resume-openai",
            payload: payload,
            timeout: 15
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let ack):
                let ok = ack.bool("ok") ?? false
                if ok {
                    return
                }

                let code = ack.string("code") ?? "internal_error"
                let message = ack.string("message") ?? "Failed to resume upstream relay stream."
                let retryable = ack.bool("retryable") ?? false
                self.handleAckError(code: code, message: message, retryable: retryable)

            case .failure(let error):
                self.latestErrorMessage = error.localizedDescription
                self.continuation?.yield(.connectionLost)
            }
        }
    }

    private func handleAckError(code: String, message: String, retryable: Bool) {
        latestErrorMessage = message

        if code == "cache_miss" {
            requestResumeOpenAIForActiveRun()
            return
        }

        if retryable {
            continuation?.yield(.connectionLost)
            return
        }

        continuation?.yield(.error(.requestFailed(message)))
        finishContinuation()
    }

    private func handleRelayEventEnvelope(_ payload: JSONDictionary) {
        guard
            let eventDict = payload.dictionary("event"),
            let eventType = eventDict.string("type"),
            let sequenceNumber = payload.int("sequenceNumber")
        else {
            return
        }

        let replay = payload.bool("replay") ?? false
        let relayRunId = payload.string("relayRunId")

        if let active = activeSubscription, let relayRunId, relayRunId != active.relayRunId {
            return
        }

        if let active = activeSubscription, sequenceNumber <= active.lastSequenceNumber {
            return
        }

        updateActiveLastSequence(sequenceNumber)
        setDeliveryState(replay: replay, sequenceNumber: sequenceNumber)

        guard let translated = OpenAIStreamEventTranslator.translate(eventType: eventType, data: eventDict) else {
            return
        }

        yieldTranslatedEvent(translated, replay: replay, sequenceNumber: sequenceNumber)
    }

    private func handleRelayDone(_ payload: JSONDictionary) {
        guard
            let statusRaw = payload.string("status"),
            let status = RelayRunStatus(rawValue: statusRaw)
        else {
            finishContinuation()
            return
        }

        if let responseId = payload.string("responseId"), !responseId.isEmpty {
            updateActiveResponseId(responseId)
        }

        if let lastSequenceNumber = payload.int("lastSequenceNumber"), lastSequenceNumber > currentLastSequenceNumber {
            updateActiveLastSequence(lastSequenceNumber)
            setDeliveryState(replay: false, sequenceNumber: lastSequenceNumber)
        }

        if didYieldTerminalEvent {
            finishContinuation()
            return
        }

        switch status {
        case .completed, .incomplete:
            if thinkingActive {
                thinkingActive = false
                yield(.thinkingFinished, replay: false, sequenceNumber: currentLastSequenceNumber)
            }
            yield(
                .completed(accumulatedText, accumulatedThinking.isEmpty ? nil : accumulatedThinking, nil),
                replay: false,
                sequenceNumber: currentLastSequenceNumber
            )
            didYieldTerminalEvent = true
            finishContinuation()

        case .failed:
            let message = latestErrorMessage ?? "Response generation failed."
            yield(.error(.requestFailed(message)), replay: false, sequenceNumber: currentLastSequenceNumber)
            didYieldTerminalEvent = true
            finishContinuation()

        case .cancelled:
            finishContinuation()

        case .starting, .streaming:
            break
        }
    }

    private func handleRelayError(_ payload: JSONDictionary) {
        let code = payload.string("code") ?? "internal_error"
        let message = payload.string("message") ?? "Unexpected relay error."
        let retryable = payload.bool("retryable") ?? false

        latestErrorMessage = message

        if code == "cache_miss" {
            requestResumeOpenAIForActiveRun()
            return
        }

        if retryable {
            continuation?.yield(.connectionLost)
            return
        }

        yield(.error(.requestFailed(message)), replay: false, sequenceNumber: currentLastSequenceNumber)
        didYieldTerminalEvent = true
        finishContinuation()
    }

    private func yieldTranslatedEvent(_ event: StreamEvent, replay: Bool, sequenceNumber: Int) {
        switch event {
        case .thinkingDelta(let delta):
            if !thinkingActive {
                thinkingActive = true
                yield(.thinkingStarted, replay: replay, sequenceNumber: sequenceNumber)
            }
            accumulatedThinking += delta
            yield(.thinkingDelta(delta), replay: replay, sequenceNumber: sequenceNumber)

        case .thinkingFinished:
            if thinkingActive {
                thinkingActive = false
                yield(.thinkingFinished, replay: replay, sequenceNumber: sequenceNumber)
            }

        case .textDelta(let delta):
            accumulatedText += delta
            yield(.textDelta(delta), replay: replay, sequenceNumber: sequenceNumber)

        case .responseCreated(let responseId):
            updateActiveResponseId(responseId)
            yield(.responseCreated(responseId), replay: replay, sequenceNumber: sequenceNumber)

        case .completed(let fullText, let fullThinking, let filePathAnns):
            if thinkingActive {
                thinkingActive = false
                yield(.thinkingFinished, replay: replay, sequenceNumber: sequenceNumber)
            }

            if !fullText.isEmpty {
                accumulatedText = fullText
            }
            if let fullThinking, !fullThinking.isEmpty {
                accumulatedThinking = fullThinking
            }

            didYieldTerminalEvent = true
            yield(
                .completed(accumulatedText, accumulatedThinking.isEmpty ? nil : accumulatedThinking, filePathAnns),
                replay: replay,
                sequenceNumber: sequenceNumber
            )
            finishContinuation()

        case .error(let error):
            if thinkingActive {
                thinkingActive = false
                yield(.thinkingFinished, replay: replay, sequenceNumber: sequenceNumber)
            }
            latestErrorMessage = error.localizedDescription
            didYieldTerminalEvent = true
            yield(.error(error), replay: replay, sequenceNumber: sequenceNumber)
            finishContinuation()

        default:
            yield(event, replay: replay, sequenceNumber: sequenceNumber)
        }
    }

    private func yield(_ event: StreamEvent, replay: Bool, sequenceNumber: Int) {
        setDeliveryState(replay: replay, sequenceNumber: sequenceNumber)
        continuation?.yield(event)
    }

    private func emitWithAck(
        event: String,
        payload: JSONDictionary,
        timeout: Double,
        completion: @escaping (Result<JSONDictionary, Error>) -> Void
    ) {
        guard let socket else {
            completion(.failure(RelayAPIServiceError.invalidResponse))
            return
        }

        socket.emitWithAck(event, payload).timingOut(after: timeout) { data in
            if let first = data.first as? String, first == "NO ACK" {
                completion(.failure(OpenAIServiceError.requestFailed("Relay socket ack timeout for \(event).")))
                return
            }

            if let ackPayload = Self.firstDictionary(from: data) {
                completion(.success(ackPayload))
            } else {
                completion(.success([:]))
            }
        }
    }

    private func finishContinuation() {
        continuation?.finish()
        continuation = nil
    }

    private func resetPerStreamState() {
        didYieldTerminalEvent = false
        thinkingActive = false
        accumulatedText = ""
        accumulatedThinking = ""
        latestErrorMessage = nil
    }

    private func resetLocked() {
        suppressDisconnectEvents = true
        finishContinuation()
        activeSubscription = nil
        resetPerStreamState()
        setDeliveryState(replay: false, sequenceNumber: 0)

        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil

        suppressDisconnectEvents = false
    }

    private func updateActiveResponseId(_ responseId: String) {
        guard var active = activeSubscription else { return }
        active.responseId = responseId
        activeSubscription = active
    }

    private func updateActiveLastSequence(_ sequenceNumber: Int) {
        guard var active = activeSubscription else {
            setDeliveryState(replay: lastDeliveredEventWasReplay, sequenceNumber: sequenceNumber)
            return
        }

        active.lastSequenceNumber = max(active.lastSequenceNumber, sequenceNumber)
        activeSubscription = active
        setDeliveryState(replay: lastDeliveredEventWasReplay, sequenceNumber: active.lastSequenceNumber)
    }

    private func setReplayFlag(_ replay: Bool) {
        lock.lock()
        _lastDeliveredEventWasReplay = replay
        lock.unlock()
    }

    private func setDeliveryState(replay: Bool, sequenceNumber: Int) {
        lock.lock()
        _lastDeliveredEventWasReplay = replay
        _currentLastSequenceNumber = max(_currentLastSequenceNumber, sequenceNumber)
        lock.unlock()
    }

    private static func firstDictionary(from data: [Any]) -> JSONDictionary? {
        for item in data {
            if let dict = item as? JSONDictionary {
                return dict
            }
            if let dict = item as? NSDictionary as? JSONDictionary {
                return dict
            }
        }
        return nil
    }

    private static func firstString(from data: [Any]) -> String? {
        for item in data {
            if let string = item as? String {
                return string
            }
        }
        return nil
    }
}
