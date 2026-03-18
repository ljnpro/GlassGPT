import ChatApplication
import ChatDomain
import ChatPresentation
import ChatRuntimeModel
import ChatRuntimePorts
import ChatRuntimeWorkflows
import Foundation
import NativeChatUI
import SwiftUI

public struct NativeChatContainerFactory {
    public init() {}

    @MainActor
    public func makePresenter() -> ChatPresenter {
        ChatPresenter(bootstrapPolicy: .live)
    }

    @MainActor
    public func makeSceneController() -> ChatSceneController {
        ChatSceneController(
            registry: RuntimeRegistryActor(),
            preparationPort: NativeChatCompositionUnavailablePreparationPort()
        )
    }

    @MainActor
    public func makeRootView() -> some View {
        NativeChatRootTabsView()
    }
}

@MainActor
private final class NativeChatCompositionUnavailablePreparationPort: SendMessagePreparationPort {
    func prepareSendMessage(text rawText: String) throws -> PreparedAssistantReply {
        throw SendMessagePreparationError.emptyInput
    }

    func uploadAttachments(_ attachments: [FileAttachment]) async -> [FileAttachment] {
        attachments
    }

    func persistUploadedAttachments(_ attachments: [FileAttachment], onUserMessageID messageID: UUID) {}
}
