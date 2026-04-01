import BackendContracts
import Foundation

extension BackendClient {
    func makeRequest(
        path: String,
        method: String,
        body: (some Encodable)?,
        authorizationMode: AuthorizationMode,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        let endpoint = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = environment.timeoutInterval
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(environment.appVersion, forHTTPHeaderField: backendAppVersionHeaderField)
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        switch authorizationMode {
        case .required:
            guard let session = sessionStore.loadSession() else {
                throw BackendAPIError.unauthorized
            }
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        case .ifAvailable:
            if let session = sessionStore.loadSession() {
                request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            }
        case .none:
            break
        }

        if let body {
            request.httpBody = try JSONEncoder.backend.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        let endpoint = environment.baseURL.appending(path: path)
        guard !queryItems.isEmpty else {
            return endpoint
        }

        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw BackendAPIError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw BackendAPIError.invalidResponse
        }
        return url
    }

    func validate(response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300, 204:
            return httpResponse
        default:
            logErrorEnvelope(data: data, statusCode: httpResponse.statusCode)

            switch httpResponse.statusCode {
            case 400:
                throw BackendAPIError.invalidRequest
            case 401:
                throw BackendAPIError.unauthorized
            case 403:
                throw BackendAPIError.forbidden
            case 404:
                throw BackendAPIError.notFound
            case 409:
                throw BackendAPIError.conflict
            case 429:
                throw BackendAPIError.rateLimited
            case 500, 502:
                throw BackendAPIError.serverError
            case 503:
                throw BackendAPIError.serviceUnavailable
            case 504:
                throw BackendAPIError.timeout
            case 501, 505 ... 599:
                throw BackendAPIError.serverError
            default:
                if !data.isEmpty, let errorSummary = String(data: data, encoding: .utf8) {
                    throw BackendAPIError.networkFailure(errorSummary)
                }
                throw BackendAPIError.invalidResponse
            }
        }
    }

    /// Attempt to decode a typed error envelope and log the requestId for debugging correlation.
    private func logErrorEnvelope(data: Data, statusCode: Int) {
        struct ErrorEnvelope: Decodable {
            let error: String
            let code: String?
            let requestId: String?
            let retryable: Bool?
        }

        guard !data.isEmpty,
              let envelope = try? JSONDecoder.backend.decode(ErrorEnvelope.self, from: data)
        else {
            return
        }

        BackendNetworkLogger.logNetworkError(
            "[HTTP] error response status=\(statusCode) error=\(envelope.error) code=\(envelope.code ?? "unknown") requestId=\(envelope.requestId ?? "unknown") retryable=\(envelope.retryable.map(String.init) ?? "unknown")"
        )
    }

    static func makeURLSession(timeoutInterval: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutInterval
        configuration.timeoutIntervalForResource = timeoutInterval
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }

    /// A dedicated URLSession for SSE streaming with no resource timeout and
    /// compression explicitly disabled so Cloudflare edge cannot buffer the stream.
    static func makeSSEURLSession(requestTimeout: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = .infinity
        configuration.waitsForConnectivity = true
        configuration.httpAdditionalHeaders = [
            "Accept-Encoding": "identity"
        ]
        return URLSession(configuration: configuration)
    }
}

enum AuthorizationMode {
    case required
    case ifAvailable
    case none

    var requiresAuthorization: Bool {
        switch self {
        case .required, .ifAvailable:
            true
        case .none:
            false
        }
    }

    var requiresSessionRefresh: Bool {
        switch self {
        case .required, .ifAvailable:
            true
        case .none:
            false
        }
    }
}

extension JSONDecoder {
    static let backend: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let backend: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}
