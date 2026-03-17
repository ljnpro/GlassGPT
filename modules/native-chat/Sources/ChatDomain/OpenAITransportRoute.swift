public enum OpenAITransportRoute: Sendable {
    case direct
    case gateway

    public var usesDirectBaseURL: Bool {
        self == .direct
    }

    public var includesCloudflareAuthorization: Bool {
        self == .gateway
    }
}
