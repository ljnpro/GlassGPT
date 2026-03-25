import ChatApplication
import ChatDomain
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatPresentation
import ChatUIComponents
import Foundation
import GeneratedFilesInfra
import OpenAITransport
import SwiftData
import Testing
@testable import NativeChatComposition

final class RuntimeTestOpenAIConfigurationProvider: OpenAIConfigurationProvider, @unchecked Sendable {
    var directOpenAIBaseURL: String
    var cloudflareGatewayBaseURL: String
    var cloudflareAIGToken: String
    var useCloudflareGateway: Bool

    init(
        directOpenAIBaseURL: String = "https://api.test.openai.local/v1",
        cloudflareGatewayBaseURL: String = "https://gateway.test.openai.local/v1",
        cloudflareAIGToken: String = "cf-test-token",
        useCloudflareGateway: Bool = false
    ) {
        self.directOpenAIBaseURL = directOpenAIBaseURL
        self.cloudflareGatewayBaseURL = cloudflareGatewayBaseURL
        self.cloudflareAIGToken = cloudflareAIGToken
        self.useCloudflareGateway = useCloudflareGateway
    }

    var openAIBaseURL: String {
        useCloudflareGateway ? cloudflareGatewayBaseURL : directOpenAIBaseURL
    }
}

final class InMemorySettingsValueStore: SettingsValueStore {
    var values: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        values[defaultName]
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName] as? String
    }

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] as? Bool ?? false
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
    }
}

final class InMemoryAPIKeyBackend: APIKeyPersisting, @unchecked Sendable {
    var storedKey: String?
    var saveError: Error?
    var didDelete = false

    func saveAPIKey(_ apiKey: String) throws(PersistenceError) {
        if let saveError {
            if let persistenceError = saveError as? PersistenceError {
                throw persistenceError
            }
            throw .keychainFailure(-1)
        }
        storedKey = apiKey
    }

    func loadAPIKey() -> String? {
        storedKey
    }

    func deleteAPIKey() {
        didDelete = true
        storedKey = nil
    }
}

enum NativeChatTestError: Error {
    case saveFailed
    case missingStubbedTransportResponse
    case timeout
}

@MainActor
func makeInMemoryModelContainer() throws -> ModelContainer {
    let schema = Schema([
        Conversation.self,
        Message.self
    ])
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(
        for: schema,
        configurations: [configuration]
    )
}

func makeTestAsyncStream<Element>() -> (
    stream: AsyncStream<Element>,
    continuation: AsyncStream<Element>.Continuation
) {
    var capturedContinuation: AsyncStream<Element>.Continuation?
    let stream = AsyncStream<Element> { continuation in
        capturedContinuation = continuation
    }
    guard let captured = capturedContinuation else {
        fatalError("AsyncStream did not call its build closure synchronously")
    }
    return (stream, captured)
}

@MainActor
final class QueuedOpenAIStreamClient: OpenAIStreamClient {
    private(set) var recordedRequests: [URLRequest] = []
    private(set) var cancelCallCount = 0
    private var scriptedStreams: [[StreamEvent]]

    init(scriptedStreams: [[StreamEvent]]) {
        self.scriptedStreams = scriptedStreams
    }

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        recordedRequests.append(request)
        let events = scriptedStreams.isEmpty ? [] : scriptedStreams.removeFirst()
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func cancel() {
        cancelCallCount += 1
    }
}

@MainActor
final class ControlledOpenAIStreamClient: OpenAIStreamClient {
    private(set) var recordedRequests: [URLRequest] = []
    private(set) var cancelCallCount = 0
    private var scriptedStreams: [[StreamEvent]]
    private var continuations: [AsyncStream<StreamEvent>.Continuation] = []

    init(scriptedStreams: [[StreamEvent]] = []) {
        self.scriptedStreams = scriptedStreams
    }

    var activeStreamCount: Int {
        continuations.count
    }

    func makeStream(request: URLRequest) -> AsyncStream<StreamEvent> {
        recordedRequests.append(request)
        if !scriptedStreams.isEmpty {
            let events = scriptedStreams.removeFirst()
            return AsyncStream { continuation in
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
        return AsyncStream { continuation in
            self.continuations.append(continuation)
        }
    }

    func cancel() {
        cancelCallCount += 1
        finishAll()
    }

    func yield(
        _ event: StreamEvent,
        onStreamAt index: Int = 0
    ) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].yield(event)
    }

    func finishStream(at index: Int = 0) {
        guard continuations.indices.contains(index) else { return }
        continuations[index].finish()
        continuations.remove(at: index)
    }

    func finishAll() {
        for continuation in continuations {
            continuation.finish()
        }
        continuations.removeAll()
    }
}

actor StubOpenAITransport: OpenAIDataTransport {
    private var queuedResponses: [Result<(Data, URLResponse), Error>] = []
    private(set) var recordedRequests: [URLRequest] = []

    func enqueue(
        data: Data,
        statusCode: Int = 200,
        url: URL = URL(
            string: "https://api.test.openai.local/v1/responses/test"
        ) ?? URL(fileURLWithPath: "/")
    ) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) ?? HTTPURLResponse()
        queuedResponses.append(.success((data, response)))
    }

    func enqueue(error: Error) {
        queuedResponses.append(.failure(error))
    }

    func data(
        for request: URLRequest
    ) async throws(OpenAIServiceError) -> (Data, URLResponse) {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else {
            throw .requestFailed("Missing stubbed transport response")
        }
        do {
            return try queuedResponses.removeFirst().get()
        } catch {
            if let serviceError = error as? OpenAIServiceError {
                throw serviceError
            }
            throw .requestFailed(error.localizedDescription)
        }
    }

    func requestedPaths() -> [String] {
        recordedRequests.compactMap { $0.url?.path }
    }

    func requests() -> [URLRequest] {
        recordedRequests
    }
}

@MainActor
struct SettingsScreenStoreHarness {
    let store: SettingsPresenter
    let settingsValueStore: InMemorySettingsValueStore
    let apiKeyBackend: InMemoryAPIKeyBackend
    let cloudflareTokenBackend: InMemoryAPIKeyBackend
    let configurationProvider: RuntimeTestOpenAIConfigurationProvider
    let transport: OpenAIDataTransport
}

private func releaseVersionsConfigURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(
            "ios/GlassGPT/Config/Versions.xcconfig"
        )
}

private func releaseVersionsConfigValues()
    -> (marketing: String, build: String) {
    let configURL = releaseVersionsConfigURL()
    guard let text = try? String(
        contentsOf: configURL,
        encoding: .utf8
    ) else {
        return ("Unknown", "?")
    }

    func value(for key: String) -> String? {
        text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let parts = line.split(
                    separator: "=",
                    maxSplits: 1
                ).map {
                    $0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                }
                guard parts.count == 2,
                      parts[0] == key else { return nil }
                return parts[1]
            }
            .first
    }

    return (
        value(for: "MARKETING_VERSION") ?? "Unknown",
        value(for: "CURRENT_PROJECT_VERSION") ?? "?"
    )
}

func currentReleaseVersionString() -> String {
    let values = releaseVersionsConfigValues()
    return "\(values.marketing) (\(values.build))"
}
