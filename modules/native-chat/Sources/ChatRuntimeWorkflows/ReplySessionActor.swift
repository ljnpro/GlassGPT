import ChatDomain
import ChatRuntimeModel
import Foundation

public actor ReplySessionActor {
    var state: ReplyRuntimeState
    var activeStreamID: UUID?

    public init(initialState: ReplyRuntimeState) {
        self.state = initialState
    }

    public func snapshot() -> ReplyRuntimeState {
        state
    }

    public func replaceState(with nextState: ReplyRuntimeState) {
        state = nextState
        activeStreamID = nil
    }

    public func isActiveStream(_ streamID: UUID) -> Bool {
        activeStreamID == streamID
    }
}
