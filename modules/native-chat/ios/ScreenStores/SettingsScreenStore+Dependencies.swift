import Foundation

extension SettingsScreenStore {
    static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var apiKeyStore: APIKeyStore {
        dependencies.apiKeyStore
    }

    var settingsStore: SettingsStore {
        dependencies.settingsStore
    }

    var openAIService: OpenAIService {
        dependencies.services.service
    }

    var requestBuilder: OpenAIRequestBuilder {
        dependencies.services.requestBuilder
    }

    var transport: OpenAIDataTransport {
        dependencies.services.transport
    }

    var configurationProvider: OpenAIConfigurationProvider {
        dependencies.services.configurationProvider
    }
}
