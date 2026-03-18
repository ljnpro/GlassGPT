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

        request.setValue(
            "Bearer \(configuration.cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }
}
