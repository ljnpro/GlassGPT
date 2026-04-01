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
