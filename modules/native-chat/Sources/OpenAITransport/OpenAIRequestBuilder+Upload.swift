import Foundation

public extension OpenAIRequestBuilder {
    /// Builds a multipart file upload request.
    /// - Parameters:
    ///   - data: The file data to upload.
    ///   - filename: The filename for the upload.
    ///   - apiKey: The API key for authentication.
    /// - Returns: A configured URL request for file upload.
    /// - Throws: ``OpenAIServiceError`` if URL construction fails.
    func uploadRequest(data: Data, filename: String, apiKey: String) throws(OpenAIServiceError) -> URLRequest {
        try requestFactory.uploadRequest(
            fileData: data,
            filename: filename,
            apiKey: apiKey
        )
    }
}
