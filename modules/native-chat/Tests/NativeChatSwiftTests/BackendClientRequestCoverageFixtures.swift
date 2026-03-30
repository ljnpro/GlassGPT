import BackendAuth
import BackendContracts
import Foundation
import Testing

func enqueueWrapperResponses() throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    try enqueueConversationResponses(encoder: encoder)
    try enqueueRunResponses(encoder: encoder)
    try enqueueAuthResponses(encoder: encoder)
}

private func enqueueConversationResponses(encoder: JSONEncoder) throws {
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(
            UserDTO(
                id: "usr_1",
                appleSubject: "apple-subject",
                displayName: "Glass User",
                email: "glass@example.com",
                createdAt: .init(timeIntervalSince1970: 1)
            )
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(
            ConversationPageDTO(
                items: [
                    ConversationDTO(
                        id: "conv_1",
                        title: "Backend Chat",
                        mode: .chat,
                        createdAt: .init(timeIntervalSince1970: 2),
                        updatedAt: .init(timeIntervalSince1970: 3),
                        lastRunID: nil,
                        lastSyncCursor: nil
                    )
                ],
                nextCursor: nil,
                hasMore: false
            )
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(
            ConversationDetailDTO(
                conversation: ConversationDTO(
                    id: "conv_1",
                    title: "Backend Chat",
                    mode: .chat,
                    createdAt: .init(timeIntervalSince1970: 2),
                    updatedAt: .init(timeIntervalSince1970: 3),
                    lastRunID: "run_1",
                    lastSyncCursor: "cur_1"
                ),
                messages: [],
                runs: []
            )
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(
            ConversationDTO(
                id: "conv_1",
                title: "Backend Chat",
                mode: .agent,
                createdAt: .init(timeIntervalSince1970: 2),
                updatedAt: .init(timeIntervalSince1970: 4),
                lastRunID: "run_1",
                lastSyncCursor: "cur_1"
            )
        )
    )
}

private func enqueueRunResponses(encoder: JSONEncoder) throws {
    let runSummary = RunSummaryDTO(
        id: "run_1",
        conversationID: "conv_1",
        kind: .chat,
        status: .completed,
        stage: nil,
        createdAt: .init(timeIntervalSince1970: 4),
        updatedAt: .init(timeIntervalSince1970: 5),
        lastEventCursor: "cur_1",
        visibleSummary: "Done",
        processSnapshotJSON: nil
    )
    for _ in 0 ..< 5 {
        try CoverageBackendURLProtocol.state.enqueueResponse(
            statusCode: 200,
            body: encoder.encode(runSummary)
        )
    }
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(SyncEnvelopeDTO(nextCursor: "cur_2", events: []))
    )
}

private func enqueueAuthResponses(encoder: JSONEncoder) throws {
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: makeCoverageSessionResponseData(
            accessToken: "apple-access-token",
            refreshToken: "apple-refresh-token",
            expiresAt: "2100-01-01T00:16:40Z"
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: makeCoverageSessionResponseData(
            accessToken: "refreshed-access-token",
            refreshToken: "refreshed-refresh-token",
            expiresAt: "2100-01-01T00:16:40Z"
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(
        statusCode: 200,
        body: encoder.encode(
            CredentialStatusDTO(
                provider: "openai",
                state: .valid,
                checkedAt: .init(timeIntervalSince1970: 6),
                lastErrorSummary: nil
            )
        )
    )
    try CoverageBackendURLProtocol.state.enqueueResponse(statusCode: 204, body: Data())
    try CoverageBackendURLProtocol.state.enqueueResponse(statusCode: 204, body: Data())
}

private func makeCoverageSessionResponseData(
    accessToken: String,
    refreshToken: String,
    expiresAt: String
) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "accessToken": accessToken,
        "refreshToken": refreshToken,
        "expiresAt": expiresAt,
        "deviceId": "device_01",
        "user": [
            "id": "usr_01",
            "appleSubject": "apple-subject-01",
            "email": "glass@example.com",
            "displayName": "Glass User",
            "createdAt": "1970-01-01T00:00:00Z"
        ]
    ])
}

func makeCoverageSessionDTO() throws -> SessionDTO {
    let data = try makeCoverageSessionResponseData(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresAt: "2100-01-01T00:16:40Z"
    )
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SessionDTO.self, from: data)
}

final class CoverageBackendURLProtocol: URLProtocol {
    static let state = CoverageBackendURLProtocolState()

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.recordRequest(request)
        let responseURL = request.url ?? URL(fileURLWithPath: "/")
        let stub = Self.state.dequeueResponse()
        let response = HTTPURLResponse(
            url: responseURL,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CoverageBackendURLProtocolState: @unchecked Sendable {
    struct StubbedResponse {
        let statusCode: Int
        let body: Data
    }

    struct RecordedRequest: Equatable {
        let path: String
        let query: String?
        let method: String
        let authorizationHeader: String?
        let body: String?
    }

    struct Snapshot {
        let recordedRequests: [RecordedRequest]
    }

    private let lock = NSLock()
    private var responseQueue: [StubbedResponse] = []
    private var recordedRequests: [RecordedRequest] = []

    func reset() {
        lock.lock()
        responseQueue.removeAll()
        recordedRequests.removeAll()
        lock.unlock()
    }

    func enqueueResponse(statusCode: Int, body: Data) throws {
        lock.lock()
        responseQueue.append(StubbedResponse(statusCode: statusCode, body: body))
        lock.unlock()
    }

    func recordRequest(_ request: URLRequest) {
        let bodyData = request.httpBody ?? readBody(from: request.httpBodyStream)
        lock.lock()
        recordedRequests.append(
            RecordedRequest(
                path: request.url?.path(percentEncoded: false)
                    ?? request.url?.path
                    ?? "",
                query: request.url?.query,
                method: request.httpMethod ?? "GET",
                authorizationHeader: request.value(forHTTPHeaderField: "Authorization"),
                body: bodyData.flatMap { String(data: $0, encoding: .utf8) }
            )
        )
        lock.unlock()
    }

    private func readBody(from stream: InputStream?) -> Data? {
        guard let stream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }

        return data.isEmpty ? nil : data
    }

    func dequeueResponse() -> StubbedResponse {
        lock.lock()
        let response = responseQueue.removeFirst()
        lock.unlock()
        return response
    }

    var snapshot: Snapshot {
        lock.lock()
        let snapshot = Snapshot(recordedRequests: recordedRequests)
        lock.unlock()
        return snapshot
    }
}
