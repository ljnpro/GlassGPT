import XCTest
import ChatDomain
import ChatPersistence
import ChatFeatures
import GeneratedFiles
import ChatRuntime
import OpenAITransport

final class SourceTargetBoundaryTests: XCTestCase {
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
            targetVersion: "4.4.0",
            supportedSourceVersions: ["4.2.4", "4.3.0", "4.3.1"],
            failureRecoveryAction: .quarantineAndRebuild
        )
        let storeURL = URL(fileURLWithPath: "/tmp/GlassGPT.sqlite")
        let timestamp = Date(timeIntervalSince1970: 0)
        let backupURL = plan.backupURL(for: storeURL, timestamp: timestamp)

        XCTAssertTrue(plan.supportsUpgrade(from: "4.3.1"))
        XCTAssertFalse(plan.supportsUpgrade(from: "4.1.0"))
        XCTAssertTrue(backupURL.path.contains("migration-backups"))
        XCTAssertEqual(backupURL.pathExtension, "sqlite")
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
