//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The speech recognition models Konfer can transcribe with.
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
/// Konfer to download or manage, but its 30 supported locales include neither
/// Swedish nor Danish, Dutch or Polish. Stock Whisper large-v3 covers the last
/// three; Swedish stays on KB-Whisper and Danish on Røst, each trained for it.
///
/// The language decides, with one exception. Each language has a default:
///
/// - **Apple** for the six languages it already covers on this Mac. Nine times
///   faster, and nothing for Konfer to download or manage.
/// - **KB-Whisper Large** for Swedish, which Apple does not support at all.
/// - **Røst v3** for Danish: the CoRal project's fine-tune of large-v3, which
///   its authors measure at 11.6% character error on conversational Danish
///   against large-v3's 27.5%.
/// - **Whisper large-v3** for Dutch and Polish, which none of the others do.
///
/// Some languages also offer large-v3 as an alternative — see
/// ``choices(for:)``. Danish, because Røst is one person's quantized
/// conversion and not yet measured here. Apple's six, because Apple was never
/// measured against Whisper on them either — only for speed, nine times
/// faster — and accents, jargon or poor audio may go the other way.
/// Transcribing the same meeting with each is how to find out.
///
public nonisolated enum ASRBackendKind: String, Codable, CaseIterable, Sendable {

    case appleSpeech = "apple-speech"
    case whisperLargeV3 = "whisper-large-v3"
    case kbWhisperSmall = "kb-whisper-small"
    case kbWhisperLarge = "kb-whisper-large"
    case roestWhisper = "roest-whisper"

    /// The model a language uses unless another is chosen.
    public init(transcribing language: MeetingLanguage) {
        switch language {
        case .english, .german, .spanish, .french, .italian, .portuguese:
            self = .appleSpeech
        case .swedish:
            self = .kbWhisperLarge
        case .danish:
            self = .roestWhisper
        case .dutch, .polish:
            self = .whisperLargeV3
        }
    }

    /// The models a language can be transcribed with, the default first.
    /// Only a language with more than one gets a choice in the Transcribe
    /// sheet.
    ///
    /// Swedish, Dutch and Polish have none: KB-Whisper is the best Swedish
    /// measured, and large-v3 is the only model here for the other two.
    public static func choices(for language: MeetingLanguage) -> [ASRBackendKind] {
        switch ASRBackendKind(transcribing: language) {
        case .roestWhisper, .appleSpeech:
            [ASRBackendKind(transcribing: language), .whisperLargeV3]
        default:
            [ASRBackendKind(transcribing: language)]
        }
    }

    /// The model a meeting was transcribed with when it didn't record one.
    ///
    /// Meetings only began recording their model when Danish got a second
    /// one, so an older meeting's model is whatever its language used then —
    /// for Danish, large-v3, not today's default.
    public static func assumed(forMeetingIn language: MeetingLanguage) -> ASRBackendKind {
        language == .danish ? .whisperLargeV3 : ASRBackendKind(transcribing: language)
    }

    /// Whether this model can transcribe a language at all.
    ///
    /// The app only offers a language's ``choices(for:)``. This guards the
    /// `KONFER_BACKEND` override, which can name a model that has no business
    /// with the recording's language: the run then fails immediately rather
    /// than after diarization has spent a minute on it.
    public func supports(_ language: MeetingLanguage) -> Bool {
        switch self {
        case .appleSpeech: ASRBackendKind(transcribing: language) == .appleSpeech
        case .kbWhisperSmall, .kbWhisperLarge: language == .swedish
        case .roestWhisper: language == .danish
        case .whisperLargeV3: true
        }
    }

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisperLargeV3: "Whisper Large v3 — multilingual"
        case .kbWhisperSmall: "KB-Whisper Small — balanced"
        case .kbWhisperLarge: "KB-Whisper Large — most accurate"
        case .roestWhisper: "Røst v3 — Danish"
        }
    }

    public var summary: String {
        switch self {
        case .appleSpeech:
            "Apple's on-device recognition. Fast, and nothing for Konfer to "
            + "download — macOS installs each language itself."
        case .whisperLargeV3:
            "OpenAI's multilingual Whisper. About 7× real time, 3 GB. Dutch "
            + "and Polish, and any language Apple or Røst does when chosen instead."
        case .kbWhisperSmall:
            "About 40× real time, 485 MB. Much better Swedish than Parakeet."
        case .kbWhisperLarge:
            "About 7× real time, 2.9 GB. The best Swedish available on-device."
        case .roestWhisper:
            "The CoRal project's Danish fine-tune of Whisper large-v3, 1.6 GB. "
            + "Its authors measure less than half large-v3's errors on "
            + "conversational Danish."
        }
    }

    /// Rough wall-clock for an hour of audio, for the Settings picker.
    public var estimatedMinutesPerHourOfAudio: Double {
        switch self {
        case .appleSpeech: 1
        case .kbWhisperSmall: 2
        // Røst is large-v3's size at 8 bits, and not yet timed here; assumed
        // no slower than large-v3 until it is.
        case .kbWhisperLarge, .whisperLargeV3, .roestWhisper: 9
        }
    }
}
