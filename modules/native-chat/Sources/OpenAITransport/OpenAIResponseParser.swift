import ChatDomain
import Foundation

/// Parses raw API response data into typed domain results.
public struct OpenAIResponseParser {
    /// Creates a new response parser.
    public init() {}

    /// Extracts the uploaded file identifier from a file upload response.
    /// - Parameters:
    ///   - responseData: The raw response data.
    ///   - response: The URL response metadata.
    /// - Returns: The API-assigned file identifier.
    /// - Throws: ``OpenAIServiceError`` if the response indicates an error or cannot be parsed.
    public func parseUploadedFileID(responseData: Data, response: URLResponse) throws(OpenAIServiceError) -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: responseData, encoding: .utf8) ?? "Upload failed"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        do {
            return try JSONCoding.decode(UploadedFileResponseDTO.self, from: responseData).id
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse upload response")
        }
    }

    /// Parses a generated title from a title generation response.
    /// - Parameters:
    ///   - data: The raw response data.
    ///   - response: The URL response metadata.
    /// - Returns: The generated title, or "New Chat" as a fallback.
    /// - Throws: ``OpenAIServiceError`` if the response indicates an HTTP error.
    public func parseGeneratedTitle(data: Data, response: URLResponse) throws(OpenAIServiceError) -> String {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIServiceError.requestFailed("Title generation failed")
        }

        let responseDTO: ResponsesResponseDTO
        do {
            responseDTO = try JSONCoding.decode(ResponsesResponseDTO.self, from: data)
        } catch {
            return "New Chat"
        }

        if let text = OpenAIStreamEventTranslator.extractOutputText(from: responseDTO) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let words = cleaned.split(separator: " ")
            if words.count > 5 {
                return words.prefix(5).joined(separator: " ")
            }
            return cleaned
        }

        return "New Chat"
    }

    /// Parses a fetched response into a structured fetch result.
    /// - Parameters:
    ///   - data: The raw response data.
    ///   - response: The URL response metadata.
    /// - Returns: A structured fetch result with status, text, and annotations.
    /// - Throws: ``OpenAIServiceError`` if the response indicates an error or cannot be parsed.
    public func parseFetchedResponse(data: Data, response: URLResponse) throws(OpenAIServiceError) -> OpenAIResponseFetchResult {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.requestFailed("Invalid response")
        }

        if httpResponse.statusCode >= 400 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Failed to fetch response"
            throw OpenAIServiceError.httpError(httpResponse.statusCode, errorMsg)
        }

        let responseDTO: ResponsesResponseDTO
        do {
            responseDTO = try JSONCoding.decode(ResponsesResponseDTO.self, from: data)
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to parse response")
        }

        let statusString = responseDTO.status ?? "unknown"
        let status = OpenAIResponseFetchResult.Status(rawValue: statusString) ?? .unknown
        let text = OpenAIStreamEventTranslator.extractOutputText(from: responseDTO) ?? ""
        let thinking = OpenAIStreamEventTranslator.extractReasoningText(from: responseDTO)
        let annotations = Self.extractCitations(from: responseDTO)
        let toolCalls = Self.extractToolCalls(from: responseDTO)
        let filePathAnnotations = OpenAIStreamEventTranslator.extractFilePathAnnotations(from: responseDTO)
        let errorMessage = OpenAIStreamEventTranslator.extractErrorMessage(from: responseDTO)

        return OpenAIResponseFetchResult(
            status: status,
            text: text,
            thinking: thinking,
            annotations: annotations,
            toolCalls: toolCalls,
            filePathAnnotations: filePathAnnotations,
            errorMessage: errorMessage
        )
    }
}
