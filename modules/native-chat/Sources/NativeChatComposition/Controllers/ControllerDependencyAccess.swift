import ChatUIComponents

@MainActor
extension ChatController {
    var hapticsEnabled: Bool {
        settingsStore.hapticEnabled
    }

    var hapticService: HapticService {
        .shared
    }
}
