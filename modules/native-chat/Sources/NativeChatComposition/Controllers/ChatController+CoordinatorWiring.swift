import Foundation

@MainActor
final class ChatControllerCoordinatorBox {
    var send: ChatSendCoordinator?
    var conversation: ChatConversationCoordinator?
    var session: ChatSessionCoordinator?
    var fileInteraction: ChatFileInteractionCoordinator?
    var lifecycle: ChatLifecycleCoordinator?
    var streaming: ChatStreamingCoordinator?
    var recovery: ChatRecoveryCoordinator?
    var generatedFilePrefetch: ChatGeneratedFilePrefetchCoordinator?
    var recoveryMaintenance: ChatRecoveryMaintenanceCoordinator?
}

@MainActor
extension ChatController {
    var sendCoordinator: ChatSendCoordinator {
        if let send = coordinatorBox.send {
            return send
        }
        let coordinator = ChatSendCoordinator(state: self, services: self)
        coordinatorBox.send = coordinator
        coordinator.conversations = conversationCoordinator
        coordinator.sessions = sessionCoordinator
        coordinator.streaming = streamingCoordinator
        return coordinator
    }

    /// Lazily builds and returns the conversation coordinator façade.
    package var conversationCoordinator: ChatConversationCoordinator {
        if let conversation = coordinatorBox.conversation {
            return conversation
        }
        let coordinator = ChatConversationCoordinator(state: self, services: self)
        coordinatorBox.conversation = coordinator
        coordinator.sessions = sessionCoordinator
        coordinator.recoveryMaintenance = recoveryMaintenanceCoordinator
        coordinator.drafts = sendCoordinator
        coordinator.streaming = streamingCoordinator
        return coordinator
    }

    var sessionCoordinator: ChatSessionCoordinator {
        if let session = coordinatorBox.session {
            return session
        }
        let coordinator = ChatSessionCoordinator(state: self, services: self)
        coordinatorBox.session = coordinator
        coordinator.conversations = conversationCoordinator
        coordinator.files = fileInteractionCoordinator
        coordinator.recovery = recoveryCoordinator
        return coordinator
    }

    var fileInteractionCoordinator: ChatFileInteractionCoordinator {
        if let fileInteraction = coordinatorBox.fileInteraction {
            return fileInteraction
        }
        let coordinator = ChatFileInteractionCoordinator(state: self, services: self)
        coordinatorBox.fileInteraction = coordinator
        coordinator.conversations = conversationCoordinator
        coordinator.prefetchCoordinator = generatedFilePrefetchCoordinator
        return coordinator
    }

    var lifecycleCoordinator: ChatLifecycleCoordinator {
        if let lifecycle = coordinatorBox.lifecycle {
            return lifecycle
        }
        let coordinator = ChatLifecycleCoordinator(state: self, services: self)
        coordinatorBox.lifecycle = coordinator
        coordinator.sessions = sessionCoordinator
        coordinator.recoveryMaintenance = recoveryMaintenanceCoordinator
        coordinator.conversations = conversationCoordinator
        return coordinator
    }

    var streamingCoordinator: ChatStreamingCoordinator {
        if let streaming = coordinatorBox.streaming {
            return streaming
        }
        let coordinator = ChatStreamingCoordinator(state: self, services: self)
        coordinatorBox.streaming = coordinator
        coordinator.sessions = sessionCoordinator
        coordinator.conversations = conversationCoordinator
        coordinator.recovery = recoveryCoordinator
        return coordinator
    }

    var recoveryCoordinator: ChatRecoveryCoordinator {
        if let recovery = coordinatorBox.recovery {
            return recovery
        }
        let coordinator = ChatRecoveryCoordinator(state: self, services: self)
        coordinatorBox.recovery = coordinator
        coordinator.conversations = conversationCoordinator
        coordinator.sessions = sessionCoordinator
        coordinator.files = fileInteractionCoordinator
        coordinator.drafts = sendCoordinator
        coordinator.streaming = streamingCoordinator
        coordinator.resultApplier.conversations = conversationCoordinator
        coordinator.resultApplier.sessions = sessionCoordinator
        coordinator.resultApplier.files = fileInteractionCoordinator
        return coordinator
    }

    var generatedFilePrefetchCoordinator: ChatGeneratedFilePrefetchCoordinator {
        if let generatedFilePrefetch = coordinatorBox.generatedFilePrefetch {
            return generatedFilePrefetch
        }
        let coordinator = ChatGeneratedFilePrefetchCoordinator(state: self, services: self)
        coordinatorBox.generatedFilePrefetch = coordinator
        coordinator.conversations = conversationCoordinator
        return coordinator
    }

    var recoveryMaintenanceCoordinator: ChatRecoveryMaintenanceCoordinator {
        if let recoveryMaintenance = coordinatorBox.recoveryMaintenance {
            return recoveryMaintenance
        }
        let coordinator = ChatRecoveryMaintenanceCoordinator(state: self, services: self)
        coordinatorBox.recoveryMaintenance = coordinator
        coordinator.conversations = conversationCoordinator
        coordinator.sessions = sessionCoordinator
        coordinator.recovery = recoveryCoordinator
        coordinator.drafts = sendCoordinator
        coordinator.streaming = streamingCoordinator
        return coordinator
    }
}
