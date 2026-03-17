import Foundation

extension OpenAIRequestBuilder {
    func uploadRequest(data: Data, filename: String, apiKey: String) throws -> URLRequest {
        let endpoint = configuration.resolvedEndpoint()

        guard let url = URL(string: "\(endpoint.baseURL)/files") else {
            throw OpenAIServiceError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        requestAuthorizer.applyAuthorization(
            to: &request,
            apiKey: apiKey,
            includeCloudflareAuthorization: endpoint.includeCloudflareAuthorization
        )

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("user_data\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(Self.mimeType(for: filename))\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        return request
    }
}
