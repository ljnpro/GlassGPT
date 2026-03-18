import Foundation

public protocol OpenAIRequestAuthorizer: Sendable {
    func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    )
}

public struct OpenAIStandardRequestAuthorizer: OpenAIRequestAuthorizer {
    private let configuration: OpenAIConfigurationProvider

    public init(configuration: OpenAIConfigurationProvider) {
        self.configuration = configuration
    }

    public func applyAuthorization(
        to request: inout URLRequest,
        apiKey: String,
        includeCloudflareAuthorization: Bool
    ) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard includeCloudflareAuthorization, configuration.usesGatewayRouting else {
            return
        }

        let aigToken = configuration.cloudflareAIGToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aigToken.isEmpty else { return }

        request.setValue("Bearer \(aigToken)", forHTTPHeaderField: "cf-aig-authorization")
    }
}
