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
/// | Whisper large-v3  | ~3 GB   | 7.5×  | (not used)    |
///
/// KB-Whisper is the National Library of Sweden's Whisper fine-tune, trained on
/// over 50,000 hours of Swedish. Apple's `SpeechTranscriber` needs nothing for
/// Snoopy to download or manage, but its 30 supported locales include neither
/// Swedish nor Danish, Dutch or Polish. Stock Whisper large-v3 covers those
/// three; Swedish stays on KB-Whisper, which was trained for it.
///
/// Which one runs is not a preference. Each row has one sensible reading, so
/// the language decides and there is no model picker to get wrong:
///
/// - **Apple** for the six languages it already covers on this Mac. Nine times
///   faster, and nothing for Snoopy to download or manage.
/// - **KB-Whisper Large** for Swedish, which Apple does not support at all.
/// - **Whisper large-v3** for Danish, Dutch and Polish, which neither of the
///   other two can do — Apple's 30 locales include none of them, and KB-Whisper
///   is a Swedish-only fine-tune.
///
public nonisolated enum ASRBackendKind: String, Codable, CaseIterable, Sendable {

    case appleSpeech = "apple-speech"
    case whisperLargeV3 = "whisper-large-v3"
    case kbWhisperSmall = "kb-whisper-small"
    case kbWhisperLarge = "kb-whisper-large"

    /// The model that transcribes a given language.
    public init(transcribing language: MeetingLanguage) {
        switch language {
        case .english, .german, .spanish, .french, .italian, .portuguese:
            self = .appleSpeech
        case .swedish:
            self = .kbWhisperLarge
        case .danish, .dutch, .polish:
            self = .whisperLargeV3
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
        case .appleSpeech: ASRBackendKind(transcribing: language) == .appleSpeech
        case .kbWhisperSmall, .kbWhisperLarge: language == .swedish
        case .whisperLargeV3: true
        }
    }

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisperLargeV3: "Whisper Large v3 — multilingual"
        case .kbWhisperSmall: "KB-Whisper Small — balanced"
        case .kbWhisperLarge: "KB-Whisper Large — most accurate"
        }
    }

    public var summary: String {
        switch self {
        case .appleSpeech:
            "Apple's on-device recognition. Fast, and nothing for Snoopy to "
            + "download — macOS installs each language itself."
        case .whisperLargeV3:
            "OpenAI's multilingual Whisper. About 7× real time, 3 GB, and the "
            + "only option here for Danish, Dutch and Polish."
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
        case .kbWhisperLarge, .whisperLargeV3: 9
        }
    }
}
