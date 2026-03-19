import ChatDomain
import ChatPersistenceSwiftData
import Foundation
import OpenAITransport
import Testing
@testable import NativeChatComposition

struct OpenAIRequestBuilderTests {
    @Test func `streaming request sets HTTP headers and URL`() throws {
        let request = try makeMultiPartStreamingRequest()

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.timeoutInterval == 300)
    }

    @Test func `streaming request payload preserves model and flags`() throws {
        let payload = try decodeMultiPartStreamingPayload()

        #expect(payload.model == ModelType.gpt5_4.rawValue)
        #expect(payload.stream == true)
        #expect(payload.store == true)
        #expect(payload.background == true)
        #expect(payload.serviceTier == ServiceTier.flex.rawValue)
        #expect(payload.reasoning?.effort == ReasoningEffort.high.rawValue)
        #expect(payload.reasoning?.summary == "auto")
    }

    @Test func `streaming request payload includes tools and input`() throws {
        let payload = try decodeMultiPartStreamingPayload()

        #expect(payload.tools.count == 3)
        #expect(payload.tools.map(\.type) == [
            "web_search_preview",
            "code_interpreter",
            "file_search"
        ])
        #expect(payload.tools.last?.vectorStoreIDs ?? [] == ["vs_123"])
        #expect(payload.input.count == 2)
        #expect(payload.input[0].role == "user")
        switch payload.input[0].content {
        case let .items(items):
            #expect(items == [
                .inputText("Describe this file"),
                .inputImage("data:image/jpeg;base64,AQI="),
                .inputFile("file_report")
            ])
        default:
            Issue.record("Expected multi-part content")
        }
        switch payload.input[1].content {
        case let .text(content):
            #expect(content == "Sure")
        default:
            Issue.record("Expected single text content")
        }
    }

    @Test func `build input messages leaves single text messages as plain strings`() {
        let input = OpenAIRequestBuilder.buildInputMessages(messages: [
            APIMessage(role: .user, content: "Hello"),
            APIMessage(role: .assistant, content: "World")
        ])

        #expect(input.count == 2)
        switch input[0].content {
        case let .text(content):
            #expect(content == "Hello")
        default:
            Issue.record("Expected text content")
        }
        switch input[1].content {
        case let .text(content):
            #expect(content == "World")
        default:
            Issue.record("Expected text content")
        }
    }

    @Test func `streaming request omits background field when disabled`() throws {
        let builder = makeDirectRequestBuilder()
        let request = try builder.streamingRequest(
            apiKey: "sk-test",
            messages: [APIMessage(role: .user, content: "Hello")],
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )

        let body = try #require(request.httpBody)
        let payload = try JSONCoding.decode(ResponsesStreamRequestDTO.self, from: body)

        #expect(payload.background == nil)
        #expect(payload.serviceTier == ServiceTier.standard.rawValue)
    }

    @Test func `fetch request includes recovery query parameters`() throws {
        let builder = makeDirectRequestBuilder()
        let request = try builder.fetchRequest(
            responseId: "resp_123",
            apiKey: "sk-test",
            useDirectBaseURL: false
        )

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let includeValues = (components.queryItems ?? [])
            .filter { $0.name == "include[]" }
            .compactMap(\.value)

        #expect(components.path == "/v1/responses/resp_123")
        #expect(Set(includeValues) == Set([
            "code_interpreter_call.outputs",
            "file_search_call.results",
            "web_search_call.action.sources"
        ]))
    }

    @Test func `recovery request uses gateway route and authorization when enabled`() throws {
        let provider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL,
            cloudflareAIGToken: "cf-test-token",
            useCloudflareGateway: true
        )
        let builder = OpenAIRequestBuilder(configuration: provider)
        let request = try builder.recoveryRequest(
            responseId: "resp_123",
            startingAfter: 9,
            apiKey: "sk-test",
            useDirectBaseURL: false
        )

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.absoluteString.hasPrefix(provider.cloudflareGatewayBaseURL))
        #expect(components.path == "/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai/responses/resp_123")
        #expect(components.queryItems?.first(where: { $0.name == "stream" })?.value == "true")
        #expect(components.queryItems?.first(where: { $0.name == "starting_after" })?.value == "9")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "cf-aig-authorization") == "Bearer cf-test-token")
    }

    @Test func `recovery request uses direct route without gateway authorization`() throws {
        let provider = DefaultOpenAIConfigurationProvider(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL,
            cloudflareAIGToken: "cf-test-token",
            useCloudflareGateway: true
        )
        let builder = OpenAIRequestBuilder(configuration: provider)
        let request = try builder.recoveryRequest(
            responseId: "resp_123",
            startingAfter: 12,
            apiKey: "sk-test",
            useDirectBaseURL: true
        )

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.absoluteString == "https://api.openai.com/v1/responses/resp_123?stream=true&starting_after=12")
        #expect(components.path == "/v1/responses/resp_123")
        #expect(components.queryItems?.first(where: { $0.name == "stream" })?.value == "true")
        #expect(components.queryItems?.first(where: { $0.name == "starting_after" })?.value == "12")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "cf-aig-authorization") == nil)
    }

    private func makeMultiPartStreamingRequest() throws -> URLRequest {
        let builder = makeDirectRequestBuilder()
        return try builder.streamingRequest(
            apiKey: "sk-test",
            messages: [
                APIMessage(
                    role: .user,
                    content: "Describe this file",
                    imageData: Data([0x01, 0x02]),
                    fileAttachments: [
                        FileAttachment(
                            filename: "report.pdf",
                            fileType: "pdf",
                            fileId: "file_report",
                            uploadStatus: .uploaded
                        )
                    ]
                ),
                APIMessage(role: .assistant, content: "Sure")
            ],
            model: .gpt5_4,
            reasoningEffort: .high,
            backgroundModeEnabled: true,
            serviceTier: .flex,
            vectorStoreIds: ["vs_123"]
        )
    }

    private func decodeMultiPartStreamingPayload() throws -> ResponsesStreamRequestDTO {
        let request = try makeMultiPartStreamingRequest()
        let body = try #require(request.httpBody)
        return try JSONCoding.decode(ResponsesStreamRequestDTO.self, from: body)
    }

    private func makeDirectRequestBuilder() -> OpenAIRequestBuilder {
        OpenAIRequestBuilder(
            configuration: DefaultOpenAIConfigurationProvider(
                directOpenAIBaseURL: "https://api.openai.com/v1",
                cloudflareGatewayBaseURL: DefaultOpenAIConfigurationProvider.defaultCloudflareGatewayBaseURL,
                cloudflareAIGToken: "",
                useCloudflareGateway: false
            )
        )
    }
}
