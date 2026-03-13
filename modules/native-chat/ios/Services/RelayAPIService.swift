import Foundation

let RELAY_HTTP_BASE_PATH = "/api/relay"
let RELAY_SOCKET_PATH = "/api/socket.io"

typealias JSONDictionary = [String: Any]

enum RelayRunStatus: String, Sendable {
    case starting
    case streaming
    case completed
    case incomplete
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .incomplete, .failed, .cancelled:
            return true
        case .starting, .streaming:
            return false
        }
    }
}

struct RelayRunStartRequest {
    let clientRequestId: String
    let conversationId: String
    let messages: [[String: Any]]
    let model: String
    let reasoningEffort: String?
    let vectorStoreIds: [String]
    let metadata: [String: Any]?

    init(
        clientRequestId: String,
        conversationId: String,
        messages: [[String: Any]],
        model: String,
        reasoningEffort: String? = nil,
        vectorStoreIds: [String] = [],
        metadata: [String: Any]? = nil
    ) {
        self.clientRequestId = clientRequestId
        self.conversationId = conversationId
        self.messages = messages
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.vectorStoreIds = vectorStoreIds
        self.metadata = metadata
    }

    var jsonObject: JSONDictionary {
        var json: JSONDictionary = [
            "clientRequestId": clientRequestId,
            "conversationId": conversationId,
            "messages": messages,
            "model": model
        ]

        if let reasoningEffort, !reasoningEffort.isEmpty {
            json["reasoningEffort"] = reasoningEffort
        }

        if !vectorStoreIds.isEmpty {
            json["vectorStoreIds"] = vectorStoreIds
        }

        if let metadata, !metadata.isEmpty {
            json["metadata"] = metadata
        }

        return json
    }
}

struct RelayRunStartResponse: Sendable {
    let relayRunId: String
    let resumeToken: String
    let status: RelayRunStatus
    let responseId: String?
}

struct RelayCancelResponse: Sendable {
    let ok: Bool
    let relayRunId: String
    let status: RelayRunStatus
    let responseId: String?
}

struct RelayFileUploadResponse: Sendable {
    let fileId: String
    let filename: String
    let contentType: String
    let bytes: Int?
}

struct RelaySnapshotStatus: Sendable {
    let responseId: String?
    let status: RelayRunStatus
    let lastSequenceNumber: Int
    let accumulatedText: String
    let accumulatedThinking: String
    let finalError: String?
}

struct RelayStatusResponse: Sendable {
    let relayRunId: String
    let conversationId: String
    let clientRequestId: String
    let responseId: String?
    let model: String
    let reasoningEffort: String
    let vectorStoreIds: [String]
    let status: RelayRunStatus
    let createdAt: Int
    let updatedAt: Int
    let expiresAt: Int
    let openAIStreamActive: Bool
    let lastSequenceNumber: Int
    let snapshot: RelaySnapshotStatus
}

struct RelayErrorPayload: Sendable {
    let relayRunId: String?
    let code: String
    let message: String
    let retryable: Bool
}

enum RelayAPIServiceError: Error, LocalizedError, Sendable {
    case relayServerURLMissing
    case invalidBaseURL(String)
    case invalidResponse
    case invalidJSONResponse
    case httpError(Int, String)
    case decodeFailure(String)

    var errorDescription: String? {
        switch self {
        case .relayServerURLMissing:
            return "Relay server URL is not configured."
        case .invalidBaseURL(let raw):
            return "Invalid relay server URL: \(raw)"
        case .invalidResponse:
            return "Invalid response from relay server."
        case .invalidJSONResponse:
            return "Relay server returned invalid JSON."
        case .httpError(let code, let message):
            return "Relay API error (\(code)): \(message)"
        case .decodeFailure(let message):
            return "Failed to decode relay response: \(message)"
        }
    }
}

// URLSession is thread-safe and this service keeps no mutable shared state.
final class RelayAPIService: @unchecked Sendable {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func configuredBaseURL() throws -> URL {
        let raw = FeatureFlags.relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)

        if !raw.isEmpty {
            guard let url = URL(string: raw) else {
                throw RelayAPIServiceError.invalidBaseURL(raw)
            }
            return url
        }

        let env = ProcessInfo.processInfo.environment
        let envURL =
            env["LIQUID_GLASS_CHAT_RELAY_SERVER_URL"] ??
            env["RELAY_SERVER_URL"] ??
            env["LIQUID_GLASS_RELAY_SERVER_URL"] ??
            ""

        let trimmedEnv = envURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEnv.isEmpty else {
            throw RelayAPIServiceError.relayServerURLMissing
        }
        guard let url = URL(string: trimmedEnv) else {
            throw RelayAPIServiceError.invalidBaseURL(trimmedEnv)
        }
        return url
    }

    func createRun(apiKey: String, request: RelayRunStartRequest) async throws -> RelayRunStartResponse {
        let url = try Self.makeRelayURL(pathComponents: ["runs"])

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(request.clientRequestId, forHTTPHeaderField: "X-Client-Request-Id")
        urlRequest.timeoutInterval = 120

        guard JSONSerialization.isValidJSONObject(request.jsonObject) else {
            throw RelayAPIServiceError.decodeFailure("Invalid run request body.")
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request.jsonObject, options: [])

        let (data, response) = try await session.data(for: urlRequest)
        let json = try Self.validateJSONResponse(data: data, response: response)

        guard
            let relayRunId = json.string("relayRunId"),
            let resumeToken = json.string("resumeToken"),
            let statusRaw = json.string("status"),
            let status = RelayRunStatus(rawValue: statusRaw)
        else {
            throw RelayAPIServiceError.decodeFailure("Missing relayRunId, resumeToken, or status.")
        }

        return RelayRunStartResponse(
            relayRunId: relayRunId,
            resumeToken: resumeToken,
            status: status,
            responseId: json.string("responseId")
        )
    }

    func cancelRun(relayRunId: String, resumeToken: String, apiKey: String) async throws -> RelayCancelResponse {
        let url = try Self.makeRelayURL(pathComponents: ["runs", relayRunId, "cancel"])

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 30
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: ["resumeToken": resumeToken], options: [])

        let (data, response) = try await session.data(for: urlRequest)
        let json = try Self.validateJSONResponse(data: data, response: response)

        guard
            let ok = json.bool("ok"),
            let returnedRelayRunId = json.string("relayRunId"),
            let statusRaw = json.string("status"),
            let status = RelayRunStatus(rawValue: statusRaw)
        else {
            throw RelayAPIServiceError.decodeFailure("Missing cancel response fields.")
        }

        return RelayCancelResponse(
            ok: ok,
            relayRunId: returnedRelayRunId,
            status: status,
            responseId: json.string("responseId")
        )
    }

    func getRunStatus(relayRunId: String, resumeToken: String) async throws -> RelayStatusResponse {
        var components = URLComponents(
            url: try Self.makeRelayURL(pathComponents: ["runs", relayRunId, "status"]),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "resumeToken", value: resumeToken)
        ]

        guard let url = components?.url else {
            throw RelayAPIServiceError.invalidResponse
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(resumeToken, forHTTPHeaderField: "X-Relay-Resume-Token")
        urlRequest.timeoutInterval = 30

        let (data, response) = try await session.data(for: urlRequest)
        let json = try Self.validateJSONResponse(data: data, response: response)

        guard
            let statusRaw = json.string("status"),
            let status = RelayRunStatus(rawValue: statusRaw),
            let snapshotDict = json.dictionary("snapshot")
        else {
            throw RelayAPIServiceError.decodeFailure("Missing status or snapshot.")
        }

        let snapshot = RelaySnapshotStatus(
            responseId: snapshotDict.string("responseId"),
            status: RelayRunStatus(rawValue: snapshotDict.string("status") ?? "") ?? status,
            lastSequenceNumber: snapshotDict.int("lastSequenceNumber") ?? 0,
            accumulatedText: snapshotDict.string("accumulatedText") ?? "",
            accumulatedThinking: snapshotDict.string("accumulatedThinking") ?? "",
            finalError: snapshotDict.string("finalError")
        )

        guard
            let returnedRelayRunId = json.string("relayRunId"),
            let conversationId = json.string("conversationId"),
            let clientRequestId = json.string("clientRequestId"),
            let model = json.string("model"),
            let reasoningEffort = json.string("reasoningEffort")
        else {
            throw RelayAPIServiceError.decodeFailure("Missing top-level status fields.")
        }

        return RelayStatusResponse(
            relayRunId: returnedRelayRunId,
            conversationId: conversationId,
            clientRequestId: clientRequestId,
            responseId: json.string("responseId"),
            model: model,
            reasoningEffort: reasoningEffort,
            vectorStoreIds: json.stringArray("vectorStoreIds"),
            status: status,
            createdAt: json.int("createdAt") ?? 0,
            updatedAt: json.int("updatedAt") ?? 0,
            expiresAt: json.int("expiresAt") ?? 0,
            openAIStreamActive: json.bool("openaiStreamActive") ?? false,
            lastSequenceNumber: json.int("lastSequenceNumber") ?? snapshot.lastSequenceNumber,
            snapshot: snapshot
        )
    }

    func uploadFile(
        apiKey: String,
        fileData: Data,
        filename: String,
        contentType: String
    ) async throws -> RelayFileUploadResponse {
        let url = try Self.makeRelayURL(pathComponents: ["files"])

        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 180

        let body = Self.makeMultipartBody(
            boundary: boundary,
            filename: filename,
            contentType: contentType,
            data: fileData
        )

        let (data, response) = try await session.upload(for: urlRequest, from: body)
        let json = try Self.validateJSONResponse(data: data, response: response)

        guard
            let fileId = json.string("fileId"),
            let returnedFilename = json.string("filename"),
            let returnedContentType = json.string("contentType")
        else {
            throw RelayAPIServiceError.decodeFailure("Missing file upload fields.")
        }

        return RelayFileUploadResponse(
            fileId: fileId,
            filename: returnedFilename,
            contentType: returnedContentType,
            bytes: json.int("bytes")
        )
    }

    private static func makeRelayURL(pathComponents: [String]) throws -> URL {
        let baseURL = try configuredBaseURL()
        let basePath = RELAY_HTTP_BASE_PATH.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        var url = baseURL.appendingPathComponent(basePath)
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }

    private static func validateJSONResponse(data: Data, response: URLResponse) throws -> JSONDictionary {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayAPIServiceError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let message = parseErrorMessage(data: data) ?? String(data: data, encoding: .utf8) ?? "Unknown relay server error"
            throw RelayAPIServiceError.httpError(httpResponse.statusCode, message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? JSONDictionary else {
            throw RelayAPIServiceError.invalidJSONResponse
        }

        return json
    }

    private static func parseErrorMessage(data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? JSONDictionary
        else {
            return nil
        }

        if let message = json.string("message"), !message.isEmpty {
            return message
        }

        if let error = json.dictionary("error"), let message = error.string("message"), !message.isEmpty {
            return message
        }

        return nil
    }

    private static func makeMultipartBody(
        boundary: String,
        filename: String,
        contentType: String,
        data: Data
    ) -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n")
        append("user_data\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")

        append("--\(boundary)--\r\n")
        return body
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String) -> Bool? {
        self[key] as? Bool
    }

    func int(_ key: String) -> Int? {
        if let value = self[key] as? Int {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.intValue
        }
        if let value = self[key] as? Double {
            return Int(value)
        }
        if let value = self[key] as? String {
            return Int(value)
        }
        return nil
    }

    func dictionary(_ key: String) -> JSONDictionary? {
        self[key] as? JSONDictionary
    }

    func stringArray(_ key: String) -> [String] {
        self[key] as? [String] ?? []
    }
}
