import Foundation

extension OpenAIRequestBuilder {
    func makeJSONRequest(
        url: URL,
        apiKey: String,
        method: String,
        accept: String,
        timeoutInterval: TimeInterval,
        includeCloudflareAuthorization: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeoutInterval
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: includeCloudflareAuthorization
        )

        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    static func makeResponseURL(
        baseURL: String,
        responseId: String,
        stream: Bool,
        startingAfter: Int?,
        include: [String]?
    ) throws -> URL {
        guard var components = URLComponents(string: "\(baseURL)/\(responseId)") else {
            throw OpenAIServiceError.invalidURL
        }

        var queryItems: [URLQueryItem] = []

        if stream {
            queryItems.append(URLQueryItem(name: "stream", value: "true"))
        }

        if let startingAfter {
            queryItems.append(URLQueryItem(name: "starting_after", value: String(startingAfter)))
        }

        if let include {
            queryItems.append(contentsOf: include.map { URLQueryItem(name: "include[]", value: $0) })
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw OpenAIServiceError.invalidURL
        }

        return url
    }
}
