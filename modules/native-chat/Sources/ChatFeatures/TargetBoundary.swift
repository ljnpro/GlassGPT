public enum ChatFeaturesBoundary {
    public struct Services<ConfigurationProvider, RequestBuilder, ResponseParser, Transport, Service> {
        public let configurationProvider: ConfigurationProvider
        public let requestBuilder: RequestBuilder
        public let responseParser: ResponseParser
        public let transport: Transport
        public let service: Service

        public init(
            configurationProvider: ConfigurationProvider,
            requestBuilder: RequestBuilder,
            responseParser: ResponseParser,
            transport: Transport,
            service: Service
        ) {
            self.configurationProvider = configurationProvider
            self.requestBuilder = requestBuilder
            self.responseParser = responseParser
            self.transport = transport
            self.service = service
        }
    }

    public struct Scope<Services, Persistence, GeneratedFiles, SettingsStore, APIKeyStore, BackgroundTasks> {
        public let services: Services
        public let persistence: Persistence
        public let generatedFiles: GeneratedFiles
        public let settingsStore: SettingsStore
        public let apiKeyStore: APIKeyStore
        public let backgroundTasks: BackgroundTasks

        public init(
            services: Services,
            persistence: Persistence,
            generatedFiles: GeneratedFiles,
            settingsStore: SettingsStore,
            apiKeyStore: APIKeyStore,
            backgroundTasks: BackgroundTasks
        ) {
            self.services = services
            self.persistence = persistence
            self.generatedFiles = generatedFiles
            self.settingsStore = settingsStore
            self.apiKeyStore = apiKeyStore
            self.backgroundTasks = backgroundTasks
        }
    }
}
