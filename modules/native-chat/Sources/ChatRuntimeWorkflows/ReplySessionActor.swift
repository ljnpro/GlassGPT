import ChatRuntimeModel
import Foundation

public actor ReplySessionActor {
    private var state: ReplyRuntimeState

    public init(initialState: ReplyRuntimeState) {
        self.state = initialState
    }

    public func snapshot() -> ReplyRuntimeState {
        state
    }

    public func transition(to lifecycle: ReplyLifecycle, cursor: StreamCursor? = nil) {
        state.lifecycle = lifecycle
        state.cursor = cursor
    }

    public func updateBuffer(_ buffer: ReplyBuffer) {
        state.buffer = buffer
    }

    public func replaceState(with nextState: ReplyRuntimeState) {
        state = nextState
    }
}
