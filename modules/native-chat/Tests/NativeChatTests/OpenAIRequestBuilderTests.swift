import ChatDomain
import ChatPersistenceSwiftData
import OpenAITransport
import XCTest
@testable import NativeChatComposition

final class OpenAIRequestBuilderTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testStreamingRequestPreservesWireDefaults() throws {
        let builder = makeDirectRequestBuilder()
        let request = try builder.streamingRequest(
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

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.timeoutInterval, 300)

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONCoding.decode(ResponsesStreamRequestDTO.self, from: body)

        XCTAssertEqual(payload.model, ModelType.gpt5_4.rawValue)
        XCTAssertEqual(payload.stream, true)
        XCTAssertEqual(payload.store, true)
        XCTAssertEqual(payload.background, true)
        XCTAssertEqual(payload.serviceTier, ServiceTier.flex.rawValue)
        XCTAssertEqual(payload.reasoning?.effort, ReasoningEffort.high.rawValue)
        XCTAssertEqual(payload.reasoning?.summary, "auto")
        XCTAssertEqual(payload.tools.count, 3)
        XCTAssertEqual(payload.tools.map(\.type), [
            "web_search_preview",
            "code_interpreter",
            "file_search"
        ])
        XCTAssertEqual(payload.tools.last?.vectorStoreIDs ?? [], ["vs_123"])
        XCTAssertEqual(payload.input.count, 2)
        XCTAssertEqual(payload.input[0].role, "user")
        switch payload.input[0].content {
        case .items(let items):
            XCTAssertEqual(items, [
                .inputText("Describe this file"),
                .inputImage("data:image/jpeg;base64,AQI="),
                .inputFile("file_report")
            ])
        default:
            XCTFail("Expected multi-part content")
        }
        switch payload.input[1].content {
        case .text(let content):
            XCTAssertEqual(content, "Sure")
        default:
            XCTFail("Expected single text content")
        }
    }

    func testBuildInputMessagesLeavesSingleTextMessagesAsPlainStrings() {
        let input = OpenAIRequestBuilder.buildInputMessages(messages: [
            APIMessage(role: .user, content: "Hello"),
            APIMessage(role: .assistant, content: "World")
        ])

        XCTAssertEqual(input.count, 2)
        switch input[0].content {
        case .text(let content):
            XCTAssertEqual(content, "Hello")
        default:
            XCTFail("Expected text content")
        }
        switch input[1].content {
        case .text(let content):
            XCTAssertEqual(content, "World")
        default:
            XCTFail("Expected text content")
        }
    }

    func testStreamingRequestOmitsBackgroundFieldWhenDisabled() throws {
        let builder = makeDirectRequestBuilder()
        let request = try builder.streamingRequest(
            apiKey: "sk-test",
            messages: [APIMessage(role: .user, content: "Hello")],
            model: .gpt5_4_pro,
            reasoningEffort: .xhigh,
            backgroundModeEnabled: false,
            serviceTier: .standard
        )

        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONCoding.decode(ResponsesStreamRequestDTO.self, from: body)

        XCTAssertNil(payload.background)
        XCTAssertEqual(payload.serviceTier, ServiceTier.standard.rawValue)
    }

    func testFetchRequestIncludesRecoveryQueryParameters() throws {
        let builder = makeDirectRequestBuilder()
        let request = try builder.fetchRequest(
            responseId: "resp_123",
            apiKey: "sk-test",
            useDirectBaseURL: false
        )

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let includeValues = (components.queryItems ?? [])
            .filter { $0.name == "include[]" }
            .compactMap(\.value)

        XCTAssertEqual(components.path, "/v1/responses/resp_123")
        XCTAssertEqual(Set(includeValues), Set([
            "code_interpreter_call.outputs",
            "file_search_call.results",
            "web_search_call.action.sources"
        ]))
    }

    func testRecoveryRequestUsesGatewayRouteAndAuthorizationWhenEnabled() throws {
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

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.absoluteString.hasPrefix(provider.cloudflareGatewayBaseURL))
        XCTAssertEqual(components.path, "/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai/responses/resp_123")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "stream" })?.value, "true")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "starting_after" })?.value, "9")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "cf-aig-authorization"), "Bearer cf-test-token")
    }

    func testRecoveryRequestUsesDirectRouteWithoutGatewayAuthorization() throws {
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

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(url.absoluteString, "https://api.openai.com/v1/responses/resp_123?stream=true&starting_after=12")
        XCTAssertEqual(components.path, "/v1/responses/resp_123")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "stream" })?.value, "true")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "starting_after" })?.value, "12")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "cf-aig-authorization"))
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
