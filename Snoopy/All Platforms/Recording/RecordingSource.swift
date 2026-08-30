//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - What to capture

/// Where the system-audio side of a recording comes from.
nonisolated enum SystemAudioSource: Hashable, Sendable {

    /// Microphone only.
    case none

    /// One application's output, via a Core Audio process tap. Notifications,
    /// music and every other app stay out of the recording, and macOS asks for
    /// no screen-recording permission.
    case app(AudioApplication)

    /// Everything the Mac plays, via ScreenCaptureKit. Simpler and gives both
    /// sides from one stream, at the cost of a Screen Recording prompt.
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

    let systemAudio: SystemAudioSource

    /// Where the finished recording is written.
    let outputURL: URL
}

// MARK: - RecordingSource

/// Captures audio into a ``TwoChannelWriter``.
///
/// Two implementations, chosen by the user rather than by us, because the
/// trade-off is real in both directions: a process tap keeps the recording free
/// of stray notifications and needs no screen-recording permission, while
/// ScreenCaptureKit is simpler and hands both sides over on one clock.
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

// MARK: - Errors

nonisolated enum RecordingError: LocalizedError {

    case microphoneAccessDenied
    case screenRecordingAccessDenied
    case noAudioDevice
    case tapCreationFailed(OSStatus)
    case aggregateDeviceFailed(OSStatus)
    case applicationNotPlayingAudio(String)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            "Snoopy isn't allowed to use the microphone."
        case .screenRecordingAccessDenied:
            "Snoopy isn't allowed to record the screen, which macOS also requires for system audio."
        case .noAudioDevice:
            "No audio input device is available."
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
            + "Recording — or record a specific app instead, which doesn't need it."
        case .applicationNotPlayingAudio:
            "Start the call or play something first, then begin recording."
        default:
            nil
        }
    }
}
