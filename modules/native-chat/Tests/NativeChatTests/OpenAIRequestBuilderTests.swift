import XCTest
@testable import NativeChat

final class OpenAIRequestBuilderTests: XCTestCase {
    private var originalGatewayEnabled = false

    override func setUp() {
        super.setUp()
        originalGatewayEnabled = SettingsStore.shared.cloudflareGatewayEnabled
        SettingsStore.shared.cloudflareGatewayEnabled = false
    }

    override func tearDown() {
        SettingsStore.shared.cloudflareGatewayEnabled = originalGatewayEnabled
        super.tearDown()
    }

    func testStreamingRequestPreservesWireDefaults() throws {
        let builder = OpenAIRequestBuilder()
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
        let tools = payload.tools
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools.map(\.type), [
            "web_search_preview",
            "code_interpreter",
            "file_search"
        ])
        XCTAssertEqual(tools.last?.vectorStoreIDs ?? [], ["vs_123"])
        let input = payload.input
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0].role, "user")
        switch input[0].content {
        case .items(let items):
            XCTAssertEqual(items, [
                .inputText("Describe this file"),
                .inputImage("data:image/jpeg;base64,AQI="),
                .inputFile("file_report")
            ])
        default:
            XCTFail("Expected multi-part content")
        }
        switch input[1].content {
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
        let builder = OpenAIRequestBuilder()
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
        let builder = OpenAIRequestBuilder()
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
        SettingsStore.shared.cloudflareGatewayEnabled = true

        let builder = OpenAIRequestBuilder()
        let request = try builder.recoveryRequest(
            responseId: "resp_123",
            startingAfter: 9,
            apiKey: "sk-test",
            useDirectBaseURL: false
        )

        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertTrue(url.absoluteString.hasPrefix(FeatureFlags.cloudflareGatewayBaseURL))
        XCTAssertEqual(components.path, "/v1/887b39f387990e7ef89e400eb228e193/glass-gpt/openai/responses/resp_123")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "stream" })?.value, "true")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "starting_after" })?.value, "9")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "cf-aig-authorization"))
    }

    func testRecoveryRequestUsesDirectRouteWithoutGatewayAuthorization() throws {
        SettingsStore.shared.cloudflareGatewayEnabled = true

        let builder = OpenAIRequestBuilder()
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
}
