//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The speech recognition models Snoopy can transcribe with.
///
/// Measured on a real 1 h 17 m Swedish meeting (M3 Ultra), transcribing the
/// same five-minute excerpt:
///
/// | Model             | Size    | Speed | Swedish       |
/// |-------------------|---------|-------|---------------|
/// | Apple Speech      | —       | fast  | not supported |
/// | KB-Whisper small  | 485 MB  | 43×   | good          |
/// | KB-Whisper large  | 2.9 GB  | 7.5×  | best          |
///
/// KB-Whisper is the National Library of Sweden's Whisper fine-tune, trained on
/// over 50,000 hours of Swedish. Apple's `SpeechTranscriber` handles English
/// with nothing for Snoopy to download or manage, but its 30 supported locales
/// do not include Swedish — which is why both are here.
///
public nonisolated enum ASRBackendKind: String, Codable, CaseIterable, Sendable {

    /// English goes to Apple, everything else to KB-Whisper Large.
    case automatic
    case appleSpeech = "apple-speech"
    case kbWhisperSmall = "kb-whisper-small"
    case kbWhisperLarge = "kb-whisper-large"

    public static let `default` = ASRBackendKind.automatic

    /// The backend that actually runs, once the meeting's language is known.
    ///
    /// Apple's transcriber has no Swedish, so `.automatic` sends anything but
    /// English to KB-Whisper rather than failing.
    public func resolved(for language: MeetingLanguage) -> ASRBackendKind {
        guard self == .automatic else { return self }
        return language == .english ? .appleSpeech : .kbWhisperLarge
    }

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .appleSpeech: "Apple Speech — English only"
        case .kbWhisperSmall: "KB-Whisper Small — balanced"
        case .kbWhisperLarge: "KB-Whisper Large — most accurate"
        }
    }

    public var summary: String {
        switch self {
        case .automatic:
            "Apple's built-in recognition for English, KB-Whisper Large for "
            + "Swedish and anything else."
        case .appleSpeech:
            "Apple's on-device recognition. Fast, nothing to download, and "
            + "English only — it has no Swedish."
        case .kbWhisperSmall:
            "About 40× real time, 485 MB. Much better Swedish than Parakeet."
        case .kbWhisperLarge:
            "About 7× real time, 2.9 GB. The best Swedish available on-device."
        }
    }

    /// Rough wall-clock for an hour of audio, for the Settings picker.
    public var estimatedMinutesPerHourOfAudio: Double {
        switch self {
        case .automatic, .appleSpeech: 1
        case .kbWhisperSmall: 2
        case .kbWhisperLarge: 9
        }
    }
}
