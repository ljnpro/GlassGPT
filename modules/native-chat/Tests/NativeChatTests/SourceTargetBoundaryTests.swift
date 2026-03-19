// swiftlint:disable file_length
import XCTest
import ChatDomain
import ChatPersistenceContracts
import ChatPersistenceCore
import ChatPersistenceSwiftData
import GeneratedFilesCore
import ChatRuntimeModel
import ChatApplication
import ChatUIComponents
import OpenAITransport
// swiftlint:disable:next type_body_length
final class SourceTargetBoundaryTests: XCTestCase {
    func testChatDomainPayloadModelsRoundTripAcrossSourceTargetBoundary() throws {
        let citations = [
            URLCitation(url: "https://example.com/a", title: "A", startIndex: 0, endIndex: 1)
        ]
        let toolCalls = [
            ToolCallInfo(id: "tool_1", type: .webSearch, status: .searching, queries: ["swift"])
        ]
        let attachments = [
            FileAttachment(filename: "notes.txt", fileSize: 42, fileType: "text/plain", uploadStatus: .uploaded)
        ]
        let fileAnnotations = [
            FilePathAnnotation(
                fileId: "file_123",
                containerId: "ctr_456",
                sandboxPath: "sandbox:/tmp/notes.txt",
                filename: "notes.txt",
                startIndex: 0,
                endIndex: 8
            )
        ]

        XCTAssertEqual(URLCitation.decode(URLCitation.encode(citations)), citations)
        XCTAssertEqual(ToolCallInfo.decode(ToolCallInfo.encode(toolCalls)), toolCalls)
        XCTAssertEqual(FileAttachment.decode(FileAttachment.encode(attachments))?.count, 1)
        XCTAssertEqual(FilePathAnnotation.decode(FilePathAnnotation.encode(fileAnnotations)), fileAnnotations)
    }

    // swiftlint:disable:next function_body_length
    func testOpenAITransportSourceDTOsRemainDirectlyConstructibleAndCodable() throws {
        let request = ResponsesStreamRequestDTO(
            model: "gpt-5.4",
            input: [
                ResponsesInputMessageDTO(
                    role: "user",
                    content: .items([
                        .inputText("Hello"),
                        .inputFile("file_123")
                    ])
                )
            ],
            stream: true,
            store: true,
            serviceTier: "default",
            tools: [
                ResponsesToolDTO(type: "web_search_preview"),
                ResponsesToolDTO(type: "code_interpreter", container: .init(type: "auto"))
            ],
            background: true,
            reasoning: ResponsesReasoningRequestDTO(effort: "high", summary: "auto")
        )
        let payload = ResponsesResponseDTO(
            id: "resp_123",
            status: "completed",
            sequenceNumber: 8,
            outputText: "Done",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "Done",
                            annotations: [
                                ResponsesAnnotationDTO(
                                    type: "url_citation",
                                    url: "https://example.com",
                                    title: "Example",
                                    startIndex: 0,
                                    endIndex: 4
                                )
                            ]
                        )
                    ]
                )
            ],
            reasoning: ResponsesReasoningDTO(
                text: "thinking",
                summary: [ResponsesTextFragmentDTO(text: "summary")]
            ),
            error: nil,
            message: nil
        )
        let envelope = ResponsesStreamEnvelopeDTO(response: payload, sequenceNumber: 8)

        let requestData = try JSONEncoder().encode(request)
        let payloadData = try JSONEncoder().encode(payload)
        let envelopeData = try JSONEncoder().encode(envelope)

        XCTAssertFalse(requestData.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(ResponsesResponseDTO.self, from: payloadData), payload)
        XCTAssertEqual(try JSONDecoder().decode(ResponsesStreamEnvelopeDTO.self, from: envelopeData).resolvedResponse, payload)
    }

    // swiftlint:disable:next function_body_length
    func testOpenAITransportSourceParserAndTranslatorRemainDirectlyCallable() throws {
        let parser = OpenAIResponseParser()
        let payload = ResponsesResponseDTO(
            status: "completed",
            output: [
                ResponsesOutputItemDTO(
                    type: "message",
                    content: [
                        ResponsesContentPartDTO(
                            type: "output_text",
                            text: "sandbox:/tmp/report.txt",
                            annotations: [
                                ResponsesAnnotationDTO(
                                    type: "file_path",
                                    startIndex: 0,
                                    endIndex: 23,
                                    fileID: "file_report",
                                    containerID: "container_123",
                                    filename: "report.txt"
                                )
                            ]
                        )
                    ]
                )
            ],
            reasoning: ResponsesReasoningDTO(text: "thinking", summary: nil)
        )
        let responseData = try JSONCoding.encode(payload)
        let response = try XCTUnwrap(
            HTTPURLResponse(
                // swiftlint:disable:next force_unwrapping
                url: URL(string: "https://example.com/responses/resp_123")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )
        )

        let parsed = try parser.parseFetchedResponse(data: responseData, response: response)
        let event = OpenAIStreamEventTranslator.translate(
            eventType: "response.completed",
            data: try JSONCoding.encode(ResponsesStreamEnvelopeDTO(response: payload))
        )

        switch parsed.status {
        case .completed:
            break
        default:
            XCTFail("Expected completed fetch result status, got \(parsed.status.rawValue)")
        }
        XCTAssertEqual(parsed.text, "sandbox:/tmp/report.txt")
        XCTAssertEqual(parsed.thinking, "thinking")
        XCTAssertEqual(parsed.filePathAnnotations.first?.fileId, "file_report")
        guard case .completed(let text, let thinking, let annotations) = event else {
            return XCTFail("Expected direct transport translation to produce completed event")
        }
        XCTAssertEqual(text, "sandbox:/tmp/report.txt")
        XCTAssertEqual(thinking, "thinking")
        XCTAssertEqual(annotations?.first?.filename, "report.txt")
    }

    func testChatUIRichTextBuilderRemovesMarkdownMarkersAcrossModes() {
        let richText = RichTextAttributedStringBuilder.parseRichText("**Bold** _italics_ `code`")
        let streamingText = RichTextAttributedStringBuilder.parseStreamingText("***Merged*** output")
        let thinkingText = RichTextAttributedStringBuilder.parseThinkingText("Reasoning **summary**")

        XCTAssertEqual(String(richText.characters), "Bold italics code")
        XCTAssertEqual(String(streamingText.characters), "Merged output")
        XCTAssertEqual(String(thinkingText.characters), "Reasoning summary")
    }

    func testGeneratedFileDescriptorNormalizesIdentifiersAndClassifiesImages() {
        let descriptor = GeneratedFileDescriptor(
            fileID: "file_123",
            containerID: " container_456 ",
            filename: " ../chart.PNG ",
            mediaType: " IMAGE/PNG "
        )

        XCTAssertEqual(descriptor.downloadKey, "container_456:file_123")
        XCTAssertEqual(descriptor.filename, "chart.PNG")
        XCTAssertEqual(descriptor.pathExtension, "png")
        XCTAssertTrue(descriptor.isImage)
        XCTAssertFalse(descriptor.isPDF)
    }

    func testGeneratedFilePolicyResolvesFilenameAndOpenBehavior() {
        let descriptor = GeneratedFileDescriptor(
            fileID: "file_123",
            filename: nil,
            mediaType: "application/pdf"
        )

        let filename = GeneratedFilePolicy.resolvedFilename(
            for: descriptor,
            responseMetadata: GeneratedFileResponseMetadata(
                suggestedFilename: " quarterly-report ",
                contentDispositionFilename: nil
            ),
            inferredExtension: ".pdf"
        )

        XCTAssertEqual(filename, "quarterly-report.pdf")
        XCTAssertEqual(GeneratedFilePolicy.cacheBucket(for: descriptor), .document)
        XCTAssertEqual(GeneratedFilePolicy.openBehavior(for: descriptor), .pdfPreview)
        XCTAssertEqual(
            GeneratedFilePolicy.cacheKey(for: descriptor),
            GeneratedFileCacheKey(identity: "file_123", bucket: .document)
        )
    }

    func testGeneratedFilePolicyFallsBackToFileIdentifier() {
        let descriptor = GeneratedFileDescriptor(fileID: "file_abc")

        XCTAssertEqual(
            GeneratedFilePolicy.resolvedFilename(
                for: descriptor,
                responseMetadata: .init(),
                inferredExtension: "bin"
            ),
            "file_abc.bin"
        )
    }

    func testGeneratedFileAnnotationMatcherPrefersFallbackAndFilenameHeuristics() {
        let matcher = GeneratedFileAnnotationMatcher()
        let fallback = FilePathAnnotation(
            fileId: "file_1",
            containerId: nil,
            sandboxPath: "/tmp/report.pdf",
            filename: "report.pdf",
            startIndex: 0,
            endIndex: 10
        )
        let alternative = FilePathAnnotation(
            fileId: "file_2",
            containerId: nil,
            sandboxPath: "/tmp/chart.png",
            filename: "chart.png",
            startIndex: 0,
            endIndex: 9
        )

        XCTAssertEqual(
            matcher.findMatchingFilePathAnnotation(
                in: [alternative, fallback],
                sandboxURL: "sandbox:/tmp/report.pdf",
                fallback: fallback
            ),
            fallback
        )
        XCTAssertEqual(
            matcher.requestedFilename(
                for: "sandbox:/tmp/chart.png",
                annotation: alternative
            ),
            "chart.png"
        )
        XCTAssertTrue(matcher.annotationCanDownloadDirectly(alternative))
    }

    func testStoredConversationSnapshotNormalizesTitleAndDetectsCustomConfiguration() {
        let snapshot = StoredConversationSnapshot(
            id: UUID(),
            title: "  Weekly planning  ",
            modelIdentifier: "gpt-5.4",
            reasoningEffortIdentifier: "high",
            backgroundModeEnabled: false,
            serviceTierIdentifier: "standard",
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.title, "Weekly planning")
        XCTAssertTrue(snapshot.hasCustomConfiguration)
    }

    func testStoredDraftSnapshotComputesRecoveryDisposition() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let staleAfter: TimeInterval = 60 * 60
        let recoverable = StoredDraftSnapshot(
            messageID: UUID(),
            conversationID: UUID(),
            responseID: "resp_123",
            lastSequenceNumber: 9,
            createdAt: referenceDate.addingTimeInterval(-100),
            updatedAt: referenceDate.addingTimeInterval(-30),
            usedBackgroundMode: true
        )
        let orphaned = StoredDraftSnapshot(
            messageID: UUID(),
            conversationID: nil,
            responseID: nil,
            lastSequenceNumber: nil,
            createdAt: referenceDate.addingTimeInterval(-100),
            updatedAt: referenceDate.addingTimeInterval(-30),
            usedBackgroundMode: false
        )
        let stale = StoredDraftSnapshot(
            messageID: UUID(),
            conversationID: UUID(),
            responseID: "resp_old",
            lastSequenceNumber: 1,
            createdAt: referenceDate.addingTimeInterval(-10_000),
            updatedAt: referenceDate.addingTimeInterval(-5_000),
            usedBackgroundMode: false
        )

        XCTAssertEqual(
            recoverable.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter),
            .recoverable
        )
        XCTAssertEqual(
            orphaned.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter),
            .orphaned
        )
        XCTAssertEqual(
            stale.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter),
            .stale
        )
    }

    func testStoreMigrationPlanBuildsBackupLocationAndSupportsVersions() {
        let plan = StoreMigrationPlan(
            targetVersion: "4.4.1",
            supportedSourceVersions: ["4.4.0"],
            failureRecoveryAction: .quarantineAndRebuild
        )
        let storeURL = URL(fileURLWithPath: "/tmp/GlassGPT.sqlite")
        let timestamp = Date(timeIntervalSince1970: 0)
        let backupURL = plan.backupURL(for: storeURL, timestamp: timestamp)

        XCTAssertTrue(plan.supportsUpgrade(from: "4.4.0"))
        XCTAssertFalse(plan.supportsUpgrade(from: "4.3.1"))
        XCTAssertTrue(backupURL.path.contains("migration-backups"))
        XCTAssertEqual(backupURL.pathExtension, "sqlite")
    }

    func testChatPersistenceSettingsStoreKeepsDefaultSelectionContract() {
        final class MemoryStore: SettingsValueStore {
            var values: [String: Any] = [:]

            func object(forKey defaultName: String) -> Any? { values[defaultName] }
            func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
            func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
            func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        }

        let valueStore = MemoryStore()
        let store = SettingsStore(valueStore: valueStore)

        XCTAssertEqual(store.defaultModel, .gpt5_4_pro)
        XCTAssertEqual(store.defaultEffort, .xhigh)
        XCTAssertEqual(store.defaultConversationConfiguration.model, .gpt5_4_pro)

        valueStore.set(ModelType.gpt5_4_pro.rawValue, forKey: SettingsStore.Keys.defaultModel)
        valueStore.set(ReasoningEffort.low.rawValue, forKey: SettingsStore.Keys.defaultEffort)

        XCTAssertEqual(store.defaultEffort, ModelType.gpt5_4_pro.defaultEffort)
        XCTAssertEqual(store.defaultConversationConfiguration.reasoningEffort, ModelType.gpt5_4_pro.defaultEffort)
    }

    func testKeychainBackendDerivesStableServiceIdentifierWithoutBundleDependency() {
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "space.manus.liquid.glass.chat.t20260308214621"),
            "space.manus.liquid.glass.chat.t20260308214621"
        )
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: nil),
            KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
        XCTAssertEqual(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "   "),
            KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
    }

    func testRuntimeSessionDecisionPolicyCoversRecoveryAndBackgroundDetachment() {
        let messageID = UUID()

        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 7
            ),
            .stream(lastSequenceNumber: 7)
        )
        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: false,
                lastSequenceNumber: 7
            ),
            .poll
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                gatewayResumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
        XCTAssertEqual(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_123",
                messageId: messageID
            ),
            RuntimePendingBackgroundCancellation(responseId: "resp_123", messageId: messageID)
        )
        XCTAssertTrue(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
    }

    func testFeatureBootstrapPolicyProfilesMatchRuntimeExpectations() {
        XCTAssertTrue(FeatureBootstrapPolicy.live.restoreLastConversation)
        XCTAssertTrue(FeatureBootstrapPolicy.live.setupLifecycleObservers)
        XCTAssertTrue(FeatureBootstrapPolicy.live.runLaunchTasks)

        XCTAssertFalse(FeatureBootstrapPolicy.testing.restoreLastConversation)
        XCTAssertFalse(FeatureBootstrapPolicy.testing.setupLifecycleObservers)
        XCTAssertFalse(FeatureBootstrapPolicy.testing.runLaunchTasks)
    }

    func testOpenAIRequestFactoryBuildsGatewayAndDirectRequests() throws {
        let configuration = SourceTargetTransportConfigurationFixture(
            directOpenAIBaseURL: "https://api.openai.com/v1",
            cloudflareGatewayBaseURL: "https://gateway.example/v1",
            cloudflareAIGToken: "gateway-token",
            useCloudflareGateway: true
        )
        let factory = OpenAIRequestFactory(configuration: configuration)

        let gatewayRequest = try factory.request(
            for: OpenAIRequestDescriptor(
                path: "/responses",
                method: "POST",
                accept: "text/event-stream",
                timeoutInterval: 300
            ),
            apiKey: "sk-test",
            body: Data("{}".utf8)
        )
        let directResponseURL = try factory.responseURL(
            responseID: "resp_123",
            stream: true,
            startingAfter: 9,
            include: ["output_text"],
            useDirectBaseURL: true
        )

        XCTAssertEqual(gatewayRequest.url?.absoluteString, "https://gateway.example/v1/responses")
        XCTAssertEqual(gatewayRequest.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(
            gatewayRequest.value(forHTTPHeaderField: "cf-aig-authorization"),
            "Bearer gateway-token"
        )
        XCTAssertEqual(
            directResponseURL.absoluteString,
            "https://api.openai.com/v1/responses/resp_123?stream=true&starting_after=9&include%5B%5D=output_text"
        )
    }
}

private struct SourceTargetTransportConfigurationFixture: OpenAIConfigurationProvider {
    let directOpenAIBaseURL: String
    let cloudflareGatewayBaseURL: String
    let cloudflareAIGToken: String
    var useCloudflareGateway: Bool
}
