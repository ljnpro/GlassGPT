import Foundation
import SwiftUI

@MainActor
extension ChatController {
    func animateStreamEvent(_ shouldAnimate: Bool, animation: Animation, updates: () -> Void) {
        streamingCoordinator.animateStreamEvent(shouldAnimate, animation: animation, updates: updates)
    }
}
