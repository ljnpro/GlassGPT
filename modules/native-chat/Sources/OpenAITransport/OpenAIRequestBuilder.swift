import Foundation

private struct StaticOpenAIConfigurationProvider: OpenAIConfigurationProvider {
    let directOpenAIBaseURL: String = "https://api.openai.com/v1"
    let cloudflareGatewayBaseURL: String = DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL
    let cloudflareAIGToken: String = ""
    var useCloudflareGateway: Bool = false
}

public struct OpenAIRequestBuilder {
    public let configuration: OpenAIConfigurationProvider
    public let requestAuthorizer: OpenAIRequestAuthorizer
    public let requestFactory: OpenAIRequestFactory

    public init(
        configuration: OpenAIConfigurationProvider,
        requestAuthorizer: OpenAIRequestAuthorizer? = nil
    ) {
        let resolvedAuthorizer = requestAuthorizer ?? OpenAIStandardRequestAuthorizer(
            configuration: configuration
        )
        self.configuration = configuration
        self.requestAuthorizer = resolvedAuthorizer
        self.requestFactory = OpenAIRequestFactory(
            configuration: configuration,
            requestAuthorizer: resolvedAuthorizer
        )
    }

    public init() {
        self.init(configuration: StaticOpenAIConfigurationProvider())
    }

    public func responsesURL(useDirectBaseURL: Bool = false) -> String {
        do {
            let url = try requestFactory.responsesURL(useDirectBaseURL: useDirectBaseURL)
            return url.absoluteString
        } catch {
            return "\(configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL).baseURL)/responses"
        }
    }
}
