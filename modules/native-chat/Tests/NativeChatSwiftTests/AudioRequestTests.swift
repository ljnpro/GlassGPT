import ChatApplication
import Foundation
import Testing

/// Tests for audio session state machine and export types.
struct AudioSessionStateTests {

    @Test func initialStateIsIdle() {
        #expect(AudioSessionState.idle == .idle)
    }

    @Test func allStatesAreDistinct() {
        #expect(AudioSessionState.idle != .recording)
        #expect(AudioSessionState.recording != .playing)
        #expect(AudioSessionState.idle != .playing)
    }

    @Test func stateEquality() {
        #expect(AudioSessionState.recording == .recording)
        #expect(AudioSessionState.playing == .playing)
    }
}
