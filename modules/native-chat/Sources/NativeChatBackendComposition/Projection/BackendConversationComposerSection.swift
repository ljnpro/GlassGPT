import ChatDomain
import ChatUIComponents
import NativeChatBackendCore
import NativeChatUI
import Observation
import SwiftUI

@MainActor
protocol BackendConversationComposerDisplaying: AnyObject, Observable {
    var selectedImageData: Data? { get set }
    var pendingAttachments: [FileAttachment] { get set }
    var isComposerStreaming: Bool { get }

    func sendMessage(text: String) -> Bool
    func stopGeneration()
    func removePendingAttachment(_ attachment: FileAttachment)
}

@MainActor
extension BackendChatController: BackendConversationComposerDisplaying {
    var isComposerStreaming: Bool {
        isStreaming
    }
}

@MainActor
extension BackendAgentController: BackendConversationComposerDisplaying {
    var isComposerStreaming: Bool {
        isRunning
    }
}

struct BackendConversationComposerSection<ViewModel: BackendConversationComposerDisplaying>: View {
    @Bindable var viewModel: ViewModel
    let composerResetToken: UUID
    let onSendAccepted: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void

    var body: some View {
        BackendConversationComposer(
            composerResetToken: composerResetToken,
            isStreaming: viewModel.isComposerStreaming,
            selectedImageData: $viewModel.selectedImageData,
            pendingAttachments: $viewModel.pendingAttachments,
            onSend: { text in
                let accepted = viewModel.sendMessage(text: text)
                if accepted {
                    onSendAccepted()
                }
                return accepted
            },
            onStop: viewModel.stopGeneration,
            onPickImage: onPickImage,
            onPickDocument: onPickDocument,
            onRemoveAttachment: viewModel.removePendingAttachment
        )
    }
}

struct BackendConversationComposer: View {
    let composerResetToken: UUID
    let isStreaming: Bool
    @Binding var selectedImageData: Data?
    @Binding var pendingAttachments: [FileAttachment]
    let onSend: (String) -> Bool
    let onStop: () -> Void
    let onPickImage: () -> Void
    let onPickDocument: () -> Void
    let onRemoveAttachment: (FileAttachment) -> Void

    var body: some View {
        MessageInputBar(
            resetToken: composerResetToken,
            isStreaming: isStreaming,
            selectedImageData: $selectedImageData,
            pendingAttachments: $pendingAttachments,
            onSend: onSend,
            onStop: onStop,
            onPickImage: onPickImage,
            onPickDocument: onPickDocument,
            onRemoveAttachment: onRemoveAttachment
        )
    }
}
