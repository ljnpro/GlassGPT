import ChatApplication
import ChatDomain
import ChatPersistenceContracts
import ChatPersistenceCore
import ChatPersistenceSwiftData
import ChatRuntimeModel
import Foundation
import GeneratedFilesCore
import OpenAITransport
import Testing

// MARK: - Generated File Policy Tests

extension SourceTargetBoundaryTests {
    @Test func `generated file policy resolves filename and open behavior`() {
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

        #expect(filename == "quarterly-report.pdf")
        #expect(GeneratedFilePolicy.cacheBucket(for: descriptor) == .document)
        #expect(GeneratedFilePolicy.openBehavior(for: descriptor) == .pdfPreview)
        #expect(
            GeneratedFilePolicy.cacheKey(for: descriptor) ==
                GeneratedFileCacheKey(identity: "file_123", bucket: .document)
        )
    }

    @Test func `generated file policy falls back to file identifier`() {
        let descriptor = GeneratedFileDescriptor(fileID: "file_abc")

        #expect(
            GeneratedFilePolicy.resolvedFilename(
                for: descriptor,
                responseMetadata: .init(),
                inferredExtension: "bin"
            ) ==
                "file_abc.bin"
        )
    }

    @Test func `generated file annotation matcher prefers fallback and filename heuristics`() {
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

        #expect(
            matcher.findMatchingFilePathAnnotation(
                in: [alternative, fallback],
                sandboxURL: "sandbox:/tmp/report.pdf",
                fallback: fallback
            ) ==
                fallback
        )
        #expect(
            matcher.requestedFilename(
                for: "sandbox:/tmp/chart.png",
                annotation: alternative
            ) ==
                "chart.png"
        )
        #expect(matcher.annotationCanDownloadDirectly(alternative))
    }
}

// MARK: - Persistence and Configuration Tests

extension SourceTargetBoundaryTests {
    @Test func `stored conversation snapshot normalizes title and detects custom configuration`() {
        let snapshot = StoredConversationSnapshot(
            id: UUID(),
            title: "  Weekly planning  ",
            modelIdentifier: "gpt-5.4",
            reasoningEffortIdentifier: "high",
            backgroundModeEnabled: false,
            serviceTierIdentifier: "standard",
            updatedAt: Date()
        )

        #expect(snapshot.title == "Weekly planning")
        #expect(snapshot.hasCustomConfiguration)
    }

    @Test func `stored draft snapshot computes recovery disposition`() {
        let referenceDate = Date(timeIntervalSince1970: 10000)
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
            createdAt: referenceDate.addingTimeInterval(-10000),
            updatedAt: referenceDate.addingTimeInterval(-5000),
            usedBackgroundMode: false
        )

        #expect(
            recoverable.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter) ==
                .recoverable
        )
        #expect(
            orphaned.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter) ==
                .orphaned
        )
        #expect(
            stale.recoveryDisposition(referenceDate: referenceDate, staleAfter: staleAfter) ==
                .stale
        )
    }

    @Test func `store migration plan builds backup location and supports versions`() {
        let plan = StoreMigrationPlan(
            targetVersion: "4.4.1",
            supportedSourceVersions: ["4.4.0"],
            failureRecoveryAction: .quarantineAndRebuild
        )
        let storeURL = URL(fileURLWithPath: "/tmp/GlassGPT.sqlite")
        let timestamp = Date(timeIntervalSince1970: 0)
        let backupURL = plan.backupURL(for: storeURL, timestamp: timestamp)

        #expect(plan.supportsUpgrade(from: "4.4.0"))
        #expect(!plan.supportsUpgrade(from: "4.3.1"))
        #expect(backupURL.path.contains("migration-backups"))
        #expect(backupURL.pathExtension == "sqlite")
    }

    @Test func `persistence timestamp formatter returns filesystem safe ISO8601 value`() {
        #expect(
            PersistenceTimestampFormatter.storePathComponent(from: Date(timeIntervalSince1970: 0))
                == "1970-01-01T00-00-00.000Z"
        )
    }

    @Test func `chat persistence settings store keeps default selection contract`() {
        final class MemoryStore: SettingsValueStore {
            var values: [String: Any] = [:]

            func object(forKey defaultName: String) -> Any? {
                values[defaultName]
            }

            func string(forKey defaultName: String) -> String? {
                values[defaultName] as? String
            }

            func bool(forKey defaultName: String) -> Bool {
                values[defaultName] as? Bool ?? false
            }

            func set(_ value: Any?, forKey defaultName: String) {
                values[defaultName] = value
            }
        }

        let valueStore = MemoryStore()
        let store = SettingsStore(valueStore: valueStore)

        #expect(store.defaultModel == .gpt5_4)
        #expect(store.defaultEffort == .high)
        #expect(store.defaultConversationConfiguration.model == .gpt5_4)

        valueStore.set(ModelType.gpt5_4_pro.rawValue, forKey: SettingsStore.Keys.defaultModel)
        valueStore.set(ReasoningEffort.low.rawValue, forKey: SettingsStore.Keys.defaultEffort)

        #expect(store.defaultEffort == ModelType.gpt5_4_pro.defaultEffort)
        #expect(store.defaultConversationConfiguration.reasoningEffort == ModelType.gpt5_4_pro.defaultEffort)
    }

    @Test func `keychain backend derives stable service identifier without bundle dependency`() {
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "space.manus.liquid.glass.chat.t20260308214621") ==
                "space.manus.liquid.glass.chat.t20260308214621"
        )
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: nil) ==
                KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
        #expect(
            KeychainAPIKeyBackend.defaultServiceIdentifier(bundleIdentifier: "   ") ==
                KeychainAPIKeyBackend.fallbackServiceIdentifier
        )
    }

    @Test func `runtime session decision policy covers recovery and background detachment`() {
        let messageID = UUID()

        #expect(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: true,
                lastSequenceNumber: 7
            ) ==
                .stream(lastSequenceNumber: 7)
        )
        #expect(
            RuntimeSessionDecisionPolicy.recoveryResumeMode(
                preferStreamingResume: true,
                usedBackgroundMode: false,
                lastSequenceNumber: 7
            ) ==
                .stream(lastSequenceNumber: 7)
        )
        #expect(
            RuntimeSessionDecisionPolicy.shouldFallbackToDirectRecoveryStream(
                cloudflareGatewayEnabled: true,
                useDirectEndpoint: false,
                resumeTimedOut: false,
                receivedAnyRecoveryEvent: false
            )
        )
        #expect(
            RuntimeSessionDecisionPolicy.pendingBackgroundCancellation(
                requestUsesBackgroundMode: true,
                responseId: "resp_123",
                messageId: messageID
            ) ==
                RuntimePendingBackgroundCancellation(responseId: "resp_123", messageId: messageID)
        )
        #expect(
            RuntimeSessionDecisionPolicy.canDetachBackgroundResponse(
                hasVisibleSession: true,
                usedBackgroundMode: true,
                responseId: "resp_123"
            )
        )
    }

    @Test func `feature bootstrap policy profiles match runtime expectations`() {
        #expect(FeatureBootstrapPolicy.live.restoreLastConversation)
        #expect(FeatureBootstrapPolicy.live.setupLifecycleObservers)
        #expect(FeatureBootstrapPolicy.live.runLaunchTasks)

        #expect(!FeatureBootstrapPolicy.testing.restoreLastConversation)
        #expect(!FeatureBootstrapPolicy.testing.setupLifecycleObservers)
        #expect(!FeatureBootstrapPolicy.testing.runLaunchTasks)
    }

    @Test func `open AI request factory builds gateway and direct requests`() throws {
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

        #expect(gatewayRequest.url?.absoluteString == "https://gateway.example/v1/responses")
        #expect(gatewayRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(
            gatewayRequest.value(forHTTPHeaderField: "cf-aig-authorization") ==
                "Bearer gateway-token"
        )
        #expect(
            directResponseURL.absoluteString ==
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
