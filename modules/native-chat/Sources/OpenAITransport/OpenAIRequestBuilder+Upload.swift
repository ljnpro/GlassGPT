import Foundation

public extension OpenAIRequestBuilder {
    func uploadRequest(data: Data, filename: String, apiKey: String) throws -> URLRequest {
        try requestFactory.uploadRequest(
            fileData: data,
            filename: filename,
            apiKey: apiKey
        )
    }
}
