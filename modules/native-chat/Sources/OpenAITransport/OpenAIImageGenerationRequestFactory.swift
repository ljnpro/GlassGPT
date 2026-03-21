import Foundation

public extension OpenAIRequestFactory {
    /// Builds a request for image generation (DALL-E / gpt-image-1).
    /// - Parameters:
    ///   - prompt: The text description of the image to generate.
    ///   - apiKey: The API key for authentication.
    ///   - model: The image generation model. Defaults to "gpt-image-1".
    ///   - size: The image dimensions. Defaults to "1024x1024".
    ///   - quality: The image quality. Defaults to "auto".
    ///   - useDirectBaseURL: Whether to force the direct OpenAI endpoint.
    /// - Returns: A configured URL request.
    /// - Throws: If URL construction fails.
    func imageGenerationRequest(
        prompt: String,
        apiKey: String,
        model: String = "gpt-image-1",
        size: String = "1024x1024",
        quality: String = "auto",
        useDirectBaseURL: Bool = false
    ) throws(OpenAIServiceError) -> URLRequest {
        let body = try JSONCoding.encode(
            ImageGenerationRequestDTO(model: model, prompt: prompt, size: size, quality: quality)
        )

        return try request(
            for: OpenAIRequestDescriptor(
                path: "/images/generations",
                method: "POST",
                timeoutInterval: 120
            ),
            apiKey: apiKey,
            body: body,
            useDirectBaseURL: useDirectBaseURL
        )
    }
}

struct ImageGenerationRequestDTO: Encodable {
    let model: String
    let prompt: String
    let size: String
    let quality: String
}
