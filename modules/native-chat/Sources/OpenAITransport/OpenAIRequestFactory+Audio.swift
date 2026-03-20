import Foundation

public extension OpenAIRequestFactory {
    /// Builds a multipart form request for audio transcription (Whisper API).
    /// - Parameters:
    ///   - audioData: The audio data to transcribe.
    ///   - apiKey: The API key for authentication.
    ///   - model: The transcription model. Defaults to "whisper-1".
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    ///   - boundary: The multipart boundary string.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func transcriptionRequest(
        audioData: Data,
        apiKey: String,
        model: String = "whisper-1",
        useDirectBaseURL: Bool = false,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) throws(OpenAIServiceError) -> URLRequest {
        var body = Data()
        let crlf = Data("\r\n".utf8)

        // Model field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"model\"\r\n\r\n".utf8))
        body.append(Data("\(model)\r\n".utf8))

        // Audio file field
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".utf8))
        body.append(Data("Content-Type: audio/m4a\r\n\r\n".utf8))
        body.append(audioData)
        body.append(crlf)

        // Closing boundary
        body.append(Data("--\(boundary)--\r\n".utf8))

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/audio/transcriptions",
                method: "POST",
                timeoutInterval: 60,
                contentType: "multipart/form-data; boundary=\(boundary)"
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }

    /// Builds a request for text-to-speech synthesis (TTS API).
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voice: The voice identifier. Defaults to "alloy".
    ///   - apiKey: The API key for authentication.
    ///   - model: The TTS model. Defaults to "tts-1".
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func speechRequest(
        text: String,
        voice: String = "alloy",
        apiKey: String,
        model: String = "tts-1",
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        let body = try JSONCoding.encode(SpeechRequestDTO(model: model, input: text, voice: voice))

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/audio/speech",
                method: "POST",
                accept: "audio/mpeg",
                timeoutInterval: 60
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}

/// Internal DTO for encoding TTS speech requests.
struct SpeechRequestDTO: Encodable {
    /// The TTS model identifier.
    let model: String
    /// The text to synthesize.
    let input: String
    /// The voice identifier.
    let voice: String
}
