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
        let crlf = "\r\n"

        // Model field
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("\(model)\(crlf)".data(using: .utf8)!)

        // Audio file field
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append(crlf.data(using: .utf8)!)

        // Closing boundary
        body.append("--\(boundary)--\(crlf)".data(using: .utf8)!)

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
        let payload: [String: String] = [
            "model": model,
            "input": text,
            "voice": voice,
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw OpenAIServiceError.requestFailed("Failed to encode speech request")
        }

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
