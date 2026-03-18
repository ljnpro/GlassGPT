import ChatDomain
import Foundation
import SwiftUI

@MainActor
extension ChatController {
    func animateStreamEvent(_ shouldAnimate: Bool, animation: Animation, updates: () -> Void) {
        if shouldAnimate {
            withAnimation(animation, updates)
        } else {
            updates()
        }
    }

    func startToolCallIfNeeded(in session: ReplySession, id: String, type: ToolCallType, animated: Bool) {
        guard StreamingTransitionReducer.startToolCallIfNeeded(in: session, id: id, type: type) else { return }
        animateStreamEvent(animated, animation: .spring(duration: 0.3)) {
            self.syncVisibleState(from: session)
        }
    }

    func setToolCallStatus(in session: ReplySession, id: String, status: ToolCallStatus, animated: Bool) {
        guard StreamingTransitionReducer.setToolCallStatus(in: session, id: id, status: status) else { return }
        animateStreamEvent(animated, animation: .easeInOut(duration: 0.2)) {
            self.syncVisibleState(from: session)
        }
    }

    func addCitationIfNeeded(in session: ReplySession, citation: URLCitation, animated: Bool) {
        guard StreamingTransitionReducer.addCitationIfNeeded(in: session, citation: citation) else { return }
        animateStreamEvent(animated, animation: .easeInOut(duration: 0.2)) {
            self.syncVisibleState(from: session)
        }
    }

    func addFilePathAnnotationIfNeeded(in session: ReplySession, annotation: FilePathAnnotation, animated: Bool) {
        guard StreamingTransitionReducer.addFilePathAnnotationIfNeeded(in: session, annotation: annotation) else { return }
        animateStreamEvent(animated, animation: .easeInOut(duration: 0.2)) {
            self.syncVisibleState(from: session)
        }
    }
}
