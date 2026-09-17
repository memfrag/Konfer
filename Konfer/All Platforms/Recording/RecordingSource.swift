//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - What to capture

/// Where the system-audio side of a recording comes from.
nonisolated enum SystemAudioSource: Hashable, Sendable {

    /// No second source: the microphone alone, and nothing at all if that is
    /// off too — which ``RecordingError/nothingToRecord`` refuses.
    case none

    /// One application's output, via a Core Audio process tap. Notifications,
    /// music and every other app stay out of the recording.
    ///
    /// This still needs the user's consent. macOS gates a tap behind *System
    /// Audio Recording* — a narrower permission than screen recording, granted
    /// in the same Settings pane — so the difference between this and
    /// ``everything`` is which permission is asked for, not whether one is.
    case app(AudioApplication)

    /// Everything the Mac plays, via ScreenCaptureKit. Simpler and gives both
    /// sides from one stream, at the cost of the full screen-recording
    /// permission.
    case everything
}

/// An application that can be recorded from.
nonisolated struct AudioApplication: Identifiable, Hashable, Sendable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
}

// MARK: - Configuration

nonisolated struct RecordingConfiguration: Sendable {

    /// `uniqueID` of the chosen input device, or nil for the system default.
    let microphoneID: String?

    /// False when the microphone is deliberately left out and only the other
    /// side is recorded, so channel 0 comes out silent.
    ///
    /// Its own flag rather than a nil `microphoneID`: nil there already means
    /// "whatever the system default is", and the chosen device has to survive
    /// being switched off so it is still there when it is switched back on.
    var recordsMicrophone: Bool = true

    let systemAudio: SystemAudioSource

    /// Where the finished recording is written.
    let outputURL: URL
}

// MARK: - RecordingSource

/// Captures audio into a ``TwoChannelWriter``.
///
/// Two implementations, chosen by the user rather than by us, because the
/// trade-off is real in both directions: a process tap keeps the recording free
/// of stray notifications and asks only for the audio rather than for the
/// screen, while ScreenCaptureKit is simpler and hands both sides over on one
/// clock.
///
/// Whichever is used, the contract is the same: the microphone becomes channel
/// 0 and the system audio channel 1. Keeping them apart is the point — it is
/// free while recording and impossible to recover afterwards.
protocol RecordingSource: Sendable {

    /// Sets up devices and permissions without capturing anything yet, so
    /// failures surface before the user believes they are recording.
    func prepare(_ configuration: RecordingConfiguration) async throws

    func start(writingTo writer: TwoChannelWriter) async throws

    /// Stops capture and releases every system resource taken in `prepare`.
    func stop() async
}

// MARK: - Privacy

/// Where macOS grants what recording needs.
///
/// Both recording permissions live in the same pane — screen recording and the
/// narrower system-audio one a process tap uses are two rows of it — which is
/// why naming the pane is not the same as naming the permission.
nonisolated enum PrivacySettings {

    static let microphone = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )

    static let screenAndSystemAudio = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
}

// MARK: - Errors

nonisolated enum RecordingError: LocalizedError {

    case microphoneAccessDenied
    case screenRecordingAccessDenied
    case noAudioDevice
    case nothingToRecord
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case applicationNotPlayingAudio(String)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            "Konfer isn't allowed to use the microphone."
        case .screenRecordingAccessDenied:
            "Konfer isn't allowed to record the screen, which macOS also requires for system audio."
        case .noAudioDevice:
            "No audio input device is available."
        case .nothingToRecord:
            "Nothing is selected to record."
        case .tapCreationFailed:
            "Couldn't tap that app's audio."
        case .aggregateDeviceFailed:
            "Couldn't combine the microphone and the app's audio."
        case .applicationNotPlayingAudio(let name):
            "\(name) isn't playing any audio."
        case .writeFailed:
            "Couldn't write the recording."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphoneAccessDenied:
            "Allow it in System Settings ▸ Privacy & Security ▸ Microphone."
        case .screenRecordingAccessDenied:
            "Allow it in System Settings ▸ Privacy & Security ▸ Screen & System Audio "
            + "Recording — or record a single app instead, which asks only to record "
            + "that app's audio."
        case .applicationNotPlayingAudio:
            "Start the call or play something first, then begin recording."
        case .nothingToRecord:
            "Turn the microphone back on, choose something to record, or both."
        default:
            nil
        }
    }

    /// Where in System Settings this can be granted, for the two errors that
    /// are a withheld permission rather than a failure.
    ///
    /// Worth offering as a button rather than only naming the pane in prose.
    /// macOS asks for a permission exactly once: a refusal is never
    /// reconsidered, `prepare` will not prompt again, and the app is left
    /// sitting in a Settings pane the user now has to find on their own. This
    /// banner is the only thing still pointing at it.
    var privacySettingsURL: URL? {
        switch self {
        case .microphoneAccessDenied: PrivacySettings.microphone
        case .screenRecordingAccessDenied: PrivacySettings.screenAndSystemAudio
        default: nil
        }
    }
}
