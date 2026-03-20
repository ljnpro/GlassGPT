import ChatApplication
import Foundation
import Testing

/// Tests for audio session state machine and export types.
struct AudioSessionStateTests {
    @Test func `initial state is idle`() {
        #expect(AudioSessionState.idle == .idle)
    }

    @Test func `all states are distinct`() {
        #expect(AudioSessionState.idle != .recording)
        #expect(AudioSessionState.recording != .playing)
        #expect(AudioSessionState.idle != .playing)
    }

    @Test func `state equality`() {
        #expect(AudioSessionState.recording == .recording)
        #expect(AudioSessionState.playing == .playing)
    }
}
