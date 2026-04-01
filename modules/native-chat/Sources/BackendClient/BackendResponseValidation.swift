import Foundation

extension BackendClient {
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
    func logErrorEnvelope(data: Data, statusCode: Int) {
        struct ErrorEnvelope: Decodable {
            let error: String
            let code: String?
            let requestId: String?
            let retryable: Bool?
        }

        guard !data.isEmpty else {
            return
        }

        do {
            let envelope = try JSONDecoder.backend.decode(ErrorEnvelope.self, from: data)
            let code = envelope.code ?? "unknown"
            let rid = envelope.requestId ?? "unknown"
            let retry = envelope.retryable.map(String.init) ?? "unknown"
            BackendNetworkLogger.logNetworkError(
                "[HTTP] error status=\(statusCode) error=\(envelope.error) code=\(code) rid=\(rid) retryable=\(retry)"
            )
        } catch {
            BackendNetworkLogger.logNetworkError(
                "[HTTP] error response status=\(statusCode) — envelope decode failed: \(error.localizedDescription)"
            )
        }
    }
}
