import Foundation
import OpenAITransport

struct OpenAIRequestBuilder {
    let configuration: OpenAIConfigurationProvider
    let requestAuthorizer: OpenAIRequestAuthorizer
    let requestFactory: OpenAIRequestFactory

    init(
        configuration: OpenAIConfigurationProvider = DefaultOpenAIConfigurationProvider.shared,
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

    func responsesURL(useDirectBaseURL: Bool = false) -> String {
        do {
            let url = try requestFactory.responsesURL(useDirectBaseURL: useDirectBaseURL)
            return url.absoluteString
        } catch {
            return "\(configuration.resolvedEndpoint(useDirectBaseURL: useDirectBaseURL).baseURL)/responses"
        }
    }
}
