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
/// Which one runs is not a preference. The table above only has one sensible
/// reading of each row: Apple for English, because it is nine times faster and
/// downloads nothing macOS doesn't already have, and KB-Whisper Large for
/// Swedish, because Apple has no Swedish at all. So the language decides, and
/// there is no model picker to get wrong.
///
public nonisolated enum ASRBackendKind: String, Codable, CaseIterable, Sendable {

    case appleSpeech = "apple-speech"
    case kbWhisperSmall = "kb-whisper-small"
    case kbWhisperLarge = "kb-whisper-large"

    /// The model that transcribes a given language.
    public init(transcribing language: MeetingLanguage) {
        switch language {
        case .english: self = .appleSpeech
        case .swedish: self = .kbWhisperLarge
        }
    }

    /// Whether this model can transcribe a language at all.
    ///
    /// Unreachable through the app, where the language picks the model. It
    /// guards the `SNOOPY_BACKEND` override, which can name a model that has
    /// no business with the recording's language: the run then fails
    /// immediately rather than after diarization has spent a minute on it.
    public func supports(_ language: MeetingLanguage) -> Bool {
        switch self {
        case .appleSpeech: language == .english
        case .kbWhisperSmall, .kbWhisperLarge: true
        }
    }

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech — English only"
        case .kbWhisperSmall: "KB-Whisper Small — balanced"
        case .kbWhisperLarge: "KB-Whisper Large — most accurate"
        }
    }

    public var summary: String {
        switch self {
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
        case .appleSpeech: 1
        case .kbWhisperSmall: 2
        case .kbWhisperLarge: 9
        }
    }
}
