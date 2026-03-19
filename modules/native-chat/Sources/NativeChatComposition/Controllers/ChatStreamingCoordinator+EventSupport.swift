import Foundation
import SwiftUI

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
