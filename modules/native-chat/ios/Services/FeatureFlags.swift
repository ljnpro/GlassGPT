import Foundation
import OpenAITransport

enum FeatureFlags {
    nonisolated(unsafe) private static let configurationProvider = DefaultOpenAIConfigurationProvider.shared

    static var cloudflareGatewayBaseURL: String {
        configurationProvider.cloudflareGatewayBaseURL
    }

    static var cloudflareAIGToken: String {
        configurationProvider.cloudflareAIGToken
    }

    static var useCloudflareGateway: Bool {
        get { configurationProvider.useCloudflareGateway }
        set {
            configurationProvider.useCloudflareGateway = newValue
        }
    }

    static var openAIBaseURL: String {
        configurationProvider.openAIBaseURL
    }

    static var directOpenAIBaseURL: String {
        configurationProvider.directOpenAIBaseURL
    }

    static func applyCloudflareAuthorization(to request: inout URLRequest) {
        let endpoint = configurationProvider.resolvedEndpoint()

        guard endpoint.includeCloudflareAuthorization else {
            return
        }

        request.setValue(
            "Bearer \(configurationProvider.cloudflareAIGToken)",
            forHTTPHeaderField: "cf-aig-authorization"
        )
    }
}
