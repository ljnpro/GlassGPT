import ChatDomain
import Foundation
import OpenAITransport
import SwiftUI

enum StreamEventDisposition {
    case continued
    case terminalCompleted
    case terminalIncomplete(String?)
    case connectionLost
    case error(OpenAIServiceError)
}

@MainActor
extension ChatStreamingCoordinator {
    func animateStreamEvent(_ shouldAnimate: Bool, animation: Animation, updates: () -> Void) {
        if shouldAnimate {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }
}
