import BackendAuth
import BackendClient
import BackendContracts
import ChatDomain
import ChatPersistenceCore
import ChatPresentation
import ChatProjectionPersistence
import ConversationSyncApplication
import Foundation
import GeneratedFilesCache
import GeneratedFilesCore
import NativeChatBackendComposition
import NativeChatBackendCore
import SwiftData
import SwiftUI
import UIKit

@MainActor
struct NativeChatBackendTestHarness {
    let client: UICoverageBackendRequester
    let sessionStore: BackendSessionStore
    let settingsStore: SettingsStore
    let loader: BackendConversationLoader
    let settingsPresenter: SettingsPresenter
    let cacheRoot: URL

    func makeShellState(selectedTab: Int = 3) -> NativeChatShellState {
        NativeChatShellState(
            chatController: makeChatController(),
            agentController: makeAgentController(),
            settingsPresenter: settingsPresenter,
            historyPresenter: HistoryPresenter(
                loadConversations: { [] },
                selectConversation: { _, _ in }
            ),
            selectedTab: selectedTab
        )
    }

    func makeChatController() -> BackendChatController {
        BackendChatController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
    }

    func makeAgentController() -> BackendAgentController {
        BackendAgentController(
            client: client,
            loader: loader,
            sessionStore: sessionStore,
            settingsStore: settingsStore
        )
    }
}

@MainActor
func makeNativeChatHarness(signedIn: Bool) throws -> NativeChatBackendTestHarness {
    let client = UICoverageBackendRequester()
    let sessionStore = BackendSessionStore(session: signedIn ? makeHarnessSession() : nil)
    let settingsStore = SettingsStore()
    let schema = Schema([Conversation.self, Message.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let projectionStore = BackendProjectionStore(
        cacheRepository: ProjectionCacheRepository(modelContext: ModelContext(container)),
        cursorStore: SyncCursorStore()
    )
    let loader = BackendConversationLoader(
        client: client,
        projectionStore: projectionStore,
        sessionStore: sessionStore
    )
    let cacheRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let cacheManager = GeneratedFileCacheManager(cacheRootOverride: cacheRoot)
    let settingsPresenter = SettingsPresenter(
        account: SettingsAccountStore(sessionStore: sessionStore, client: client),
        credentials: SettingsCredentialsStore(client: client, sessionStore: sessionStore),
        defaults: SettingsDefaultsStore(settingsStore: settingsStore),
        agentDefaults: AgentSettingsDefaultsStore(settingsStore: settingsStore),
        cache: SettingsCacheStore(
            generatedImageCacheLimitString: "250 MB",
            generatedDocumentCacheLimitString: "250 MB",
            cacheManager: cacheManager
        ),
        about: SettingsAboutInfo(appVersionString: "5.0.0 (50000)", platformString: "iOS 26.4")
    )

    return NativeChatBackendTestHarness(
        client: client,
        sessionStore: sessionStore,
        settingsStore: settingsStore,
        loader: loader,
        settingsPresenter: settingsPresenter,
        cacheRoot: cacheRoot
    )
}

@MainActor
func hostView(
    _ view: some View,
    size: CGSize = CGSize(width: 430, height: 932),
    runLoopDelay: TimeInterval = 0.2
) {
    _ = hostViewController(view, size: size, runLoopDelay: runLoopDelay)
}

@discardableResult
@MainActor
func hostViewController(
    _ view: some View,
    size: CGSize = CGSize(width: 430, height: 932),
    runLoopDelay: TimeInterval = 0.2
) -> UIHostingController<AnyView> {
    let controller = UIHostingController(
        rootView: AnyView(view.environment(\.hapticsEnabled, true))
    )
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.loadViewIfNeeded()
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    drainMainRunLoop(runLoopDelay)
    controller.view.layoutIfNeeded()
    return controller
}

@MainActor
func drainMainRunLoop(_ delay: TimeInterval = 0.2) {
    RunLoop.current.run(until: Date().addingTimeInterval(delay))
}

@MainActor
func firstSubview<T: UIView>(
    in root: UIView,
    matching identifier: String,
    as type: T.Type = T.self
) -> T? {
    if let typedRoot = root as? T, typedRoot.accessibilityIdentifier == identifier {
        return typedRoot
    }

    for subview in root.subviews {
        if let match: T = firstSubview(in: subview, matching: identifier, as: type) {
            return match
        }
    }

    return nil
}

@MainActor
func tapControl(withIdentifier identifier: String, in root: UIView) {
    guard let control: UIControl = firstSubview(in: root, matching: identifier) else {
        return
    }

    control.sendActions(for: .touchUpInside)
}

@MainActor
func setSwitch(withIdentifier identifier: String, isOn: Bool, in root: UIView) {
    guard let control: UISwitch = firstSubview(in: root, matching: identifier) else {
        return
    }

    control.setOn(isOn, animated: false)
    control.sendActions(for: .valueChanged)
}

@MainActor
func setSlider(withIdentifier identifier: String, value: Float, in root: UIView) {
    guard let slider: UISlider = firstSubview(in: root, matching: identifier) else {
        return
    }

    slider.value = value
    slider.sendActions(for: .valueChanged)
}

func makeHarnessSession() -> SessionDTO {
    SessionDTO(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: .init(timeIntervalSince1970: 4000),
        deviceID: "device_1",
        user: UserDTO(
            id: "user_1",
            appleSubject: "apple-user",
            displayName: "Taylor",
            email: "taylor@example.com",
            createdAt: .init(timeIntervalSince1970: 1)
        )
    )
}

func makeHarnessConversation(
    serverID: String = "conv_1",
    accountID: String = "user_1",
    mode: ConversationMode = .chat
) -> Conversation {
    Conversation(
        serverID: serverID,
        syncAccountID: accountID,
        title: mode == .agent ? "Agent Run" : "Chat Thread",
        createdAt: .init(timeIntervalSince1970: 10),
        updatedAt: .init(timeIntervalSince1970: 20),
        lastRunServerID: "run_1",
        lastSyncCursor: "cursor_1",
        modeRawValue: mode == .chat ? nil : mode.rawValue
    )
}

func makeBackendMessageSurface(
    role: MessageRole = .assistant,
    content: String = "Rendered message",
    isComplete: Bool = true,
    includeTrace: Bool = false,
    toolCalls: [ToolCallInfo] = [
        ToolCallInfo(id: "tool_1", type: .codeInterpreter, status: .completed, code: "print(1)", results: ["1"])
    ]
) -> BackendMessageSurface {
    let message = Message(
        role: role,
        content: content,
        thinking: role == .assistant ? "Reasoning" : nil,
        isComplete: isComplete,
        annotations: [URLCitation(url: "https://example.com", title: "Example", startIndex: 0, endIndex: 7)],
        toolCalls: toolCalls,
        fileAttachments: [FileAttachment(filename: "report.pdf", fileSize: 12, fileType: "pdf", fileId: "file_1", uploadStatus: .uploaded)],
        filePathAnnotations: [
            FilePathAnnotation(
                fileId: "file_1",
                containerId: "container_1",
                sandboxPath: "/tmp/report.pdf",
                filename: "report.pdf",
                startIndex: 0,
                endIndex: 4
            )
        ],
        agentTrace: includeTrace ? makeAgentTurnTrace() : nil
    )
    return BackendMessageSurface(message: message)
}

func makeAgentTurnTrace() -> AgentTurnTrace {
    AgentTurnTrace(
        leaderBriefSummary: "Leader summary",
        workerSummaries: [AgentWorkerSummary(role: .workerA, summary: "Worker summary")],
        processSnapshot: AgentProcessSnapshot(
            activity: .synthesis,
            currentFocus: "Finish synthesis",
            leaderLiveStatus: "Synthesizing",
            leaderLiveSummary: "Combining worker output"
        ),
        completedStage: .finalSynthesis,
        outcome: "Completed"
    )
}
