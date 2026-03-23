@preconcurrency import AVFoundation
import Foundation
import Observation

/// The current state of the audio session.
public enum AudioSessionState: Sendable, Equatable {
    /// No audio activity.
    case idle
    /// Recording audio from the microphone.
    case recording
    /// Playing back synthesized audio.
    case playing
}

/// Manages audio recording and playback for voice input/output.
///
/// Wraps `AVAudioSession`, `AVAudioRecorder`, and `AVAudioPlayer` to provide
/// a simple state-machine interface for the chat UI.
@MainActor
@Observable
public final class AudioSessionManager: NSObject, Sendable {
    /// The current state of the audio session.
    public private(set) var state: AudioSessionState = .idle

    /// The recorded audio data after a recording session completes.
    public private(set) var recordedAudioData: Data?

    /// Whether microphone permission has been granted.
    public private(set) var hasMicrophonePermission = false

    /// The audio recorder for capturing microphone input.
    private var audioRecorder: AVAudioRecorder?
    /// The audio player for TTS playback.
    private var audioPlayer: AVAudioPlayer?
    /// The file URL for the temporary recording.
    private var recordingURL: URL?

    /// Creates a new audio session manager.
    override public init() {
        super.init()
    }

    /// Requests microphone permission if not already granted.
    public func requestMicrophonePermission() async {
        if AVAudioApplication.shared.recordPermission == .granted {
            hasMicrophonePermission = true
            return
        }

        let granted = await AVAudioApplication.requestRecordPermission()
        hasMicrophonePermission = granted
    }

    /// Starts recording audio from the microphone.
    /// - Returns: `true` if recording started successfully.
    @discardableResult
    public func startRecording() -> Bool {
        guard hasMicrophonePermission, state == .idle else {
            return false
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("glassgpt_recording_\(UUID().uuidString).m4a")
        recordingURL = url

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
            let fallbackFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 44100,
                channels: 1,
                interleaved: false
            )
            guard let recorderFormat = format ?? fallbackFormat else {
                state = .idle
                return false
            }
            audioRecorder = try AVAudioRecorder(url: url, format: recorderFormat)
            audioRecorder?.record()
            state = .recording
            return true
        } catch {
            state = .idle
            return false
        }
    }

    /// Stops recording and captures the audio data.
    public func stopRecording() {
        guard state == .recording else { return }

        audioRecorder?.stop()
        audioRecorder = nil

        if let url = recordingURL {
            do {
                recordedAudioData = try Data(contentsOf: url)
            } catch {
                recordedAudioData = nil
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                // Best-effort cleanup; the temporary file will be
                // reclaimed by the system on the next temp purge.
            }
        }

        recordingURL = nil
        state = .idle
    }

    /// Plays audio data (e.g., TTS output).
    /// - Parameter data: The audio data to play.
    public func playAudio(_ data: Data) {
        guard state == .idle else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            state = .playing
        } catch {
            state = .idle
        }
    }

    /// Stops any active playback.
    public func stopPlayback() {
        guard state == .playing else { return }
        audioPlayer?.stop()
        audioPlayer = nil
        state = .idle
    }

    /// Clears the recorded audio data.
    public func clearRecordedData() {
        recordedAudioData = nil
    }
}

extension AudioSessionManager: AVAudioPlayerDelegate {
    /// Called when audio playback finishes.
    nonisolated public func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            self.state = .idle
            self.audioPlayer = nil
        }
    }
}
