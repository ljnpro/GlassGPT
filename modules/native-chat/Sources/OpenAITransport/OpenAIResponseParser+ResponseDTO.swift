import Foundation

public extension OpenAIResponseParser {
    /// Parses a top-level Responses API payload into a response DTO.
    func parseResponseDTO(
        data: Data,
        response: URLResponse
    ) throws(OpenAIServiceError) -> ResponsesResponseDTO {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Request failed"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMessage)
        }

        return try JSONCoding.decode(ResponsesResponseDTO.self, from: data)
    }
}
