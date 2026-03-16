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
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])

        XCTAssertEqual(json["model"] as? String, ModelType.gpt5_4.rawValue)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["store"] as? Bool, true)
        XCTAssertEqual(json["background"] as? Bool, true)
        XCTAssertEqual(json["service_tier"] as? String, ServiceTier.flex.rawValue)
        XCTAssertEqual(reasoning["effort"] as? String, ReasoningEffort.high.rawValue)
        XCTAssertEqual(reasoning["summary"] as? String, "auto")
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools.compactMap { $0["type"] as? String }, [
            "web_search_preview",
            "code_interpreter",
            "file_search"
        ])
        XCTAssertEqual((tools.last?["vector_store_ids"] as? [String]) ?? [], ["vs_123"])
        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["role"] as? String, "user")
        XCTAssertNotNil(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(input[1]["content"] as? String, "Sure")
    }

    func testBuildInputArrayLeavesSingleTextMessagesAsPlainStrings() {
        let input = OpenAIRequestBuilder.buildInputArray(messages: [
            APIMessage(role: .user, content: "Hello"),
            APIMessage(role: .assistant, content: "World")
        ])

        XCTAssertEqual(input.count, 2)
        XCTAssertEqual(input[0]["content"] as? String, "Hello")
        XCTAssertEqual(input[1]["content"] as? String, "World")
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
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertNil(json["background"])
        XCTAssertEqual(json["service_tier"] as? String, ServiceTier.standard.rawValue)
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
