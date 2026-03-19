/// Determines how API requests are routed to the OpenAI backend.
public enum OpenAITransportRoute: Sendable {
    /// Connect directly to the OpenAI API endpoint.
    case direct
    /// Route requests through a Cloudflare gateway proxy.
    case gateway

    /// Whether this route connects directly to the OpenAI base URL.
    public var usesDirectBaseURL: Bool {
        self == .direct
    }

    /// Whether this route requires Cloudflare authorization headers.
    public var includesCloudflareAuthorization: Bool {
        self == .gateway
    }
}
