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
/// | Pianissimo        | 630 MB  | 120×  | good, faster  |
/// | Whisper large-v3  | ~3 GB   | 7.5×  | (not used)    |
///
/// KB-Whisper is the National Library of Sweden's Whisper fine-tune, trained on
/// over 50,000 hours of Swedish. Apple's `SpeechTranscriber` needs nothing for
/// Konfer to download or manage, but its 30 supported locales include neither
/// Swedish nor Danish, Dutch or Polish. Stock Whisper large-v3 covers the last
/// three; Swedish stays on KB-Whisper, which was trained for it.
///
/// The language decides, with one exception. Each language has a default:
///
/// - **Apple** for the six languages it already covers on this Mac. Nine times
///   faster, and nothing for Konfer to download or manage.
/// - **KB-Whisper Large** for Swedish, which Apple does not support at all.
/// - **Whisper large-v3** for Danish, Dutch and Polish, which none of the
///   others do. Danish had a fine-tune of its own, Røst v3, until it lost to
///   large-v3 on a real meeting — see ``roestWhisper``.
///
/// Apple's six also offer large-v3 as an alternative — see ``choices(for:)`` —
/// because Apple was never measured against Whisper on them — only for speed,
/// nine times faster — and accents, jargon or poor audio may go the other way.
/// Swedish offers Pianissimo beside KB-Whisper for the same reason in reverse:
/// sixteen times faster, measured on one meeting, read against KB-Whisper by
/// nobody yet. Transcribing the same meeting with each is how to find out.
///
public nonisolated enum ASRBackendKind: String, Codable, CaseIterable, Sendable {

    case appleSpeech = "apple-speech"
    case whisperLargeV3 = "whisper-large-v3"
    case kbWhisperSmall = "kb-whisper-small"
    case kbWhisperLarge = "kb-whisper-large"

    /// Pianissimo, Klang AI's Swedish fine-tune of Parakeet TDT v3, run from
    /// Konfer's own 120-second conversion — see ``ParakeetBackend``. Swedish's
    /// second choice: KB-Whisper Large stays the default.
    case pianissimo = "pianissimo-sv"

    /// Røst v3, the CoRal project's Danish fine-tune of large-v3, which 1.4
    /// offered as Danish's default. Removed: on a real Danish meeting it
    /// transcribed worse than stock large-v3, whatever its authors' benchmark
    /// said.
    ///
    /// Kept only so the meetings it made still decode — ``MeetingStore``
    /// drops what it cannot read, and they would vanish from the library —
    /// and still say what made them. Nothing routes to it, nothing offers it,
    /// and it supports no language, so the pipeline refuses it before
    /// anything asks for a backend.
    case roestWhisper = "roest-whisper"

    /// The model a language uses unless another is chosen.
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

    /// The models a language can be transcribed with, the default first.
    /// Only a language with more than one gets a choice in the Transcribe
    /// sheet.
    ///
    /// Apple's languages can have large-v3 instead, and Swedish Pianissimo.
    /// Danish, Dutch and Polish have none: large-v3 is the only model here
    /// that speaks them.
    public static func choices(for language: MeetingLanguage) -> [ASRBackendKind] {
        switch ASRBackendKind(transcribing: language) {
        case .appleSpeech:
            [.appleSpeech, .whisperLargeV3]
        case .kbWhisperLarge:
            [.kbWhisperLarge, .pianissimo]
        default:
            [ASRBackendKind(transcribing: language)]
        }
    }

    /// The model a meeting was transcribed with when it didn't record one.
    ///
    /// Meetings only began recording their model when Danish got a second
    /// one, so an older meeting's model is whatever its language used then.
    /// For every language that is also today's default — Danish's included,
    /// now that it is large-v3 again.
    public static func assumed(forMeetingIn language: MeetingLanguage) -> ASRBackendKind {
        ASRBackendKind(transcribing: language)
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
        case .kbWhisperSmall, .kbWhisperLarge, .pianissimo: language == .swedish
        case .whisperLargeV3: true
        case .roestWhisper: false
        }
    }

    public var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisperLargeV3: "Whisper Large v3 — multilingual"
        case .kbWhisperSmall: "KB-Whisper Small — balanced"
        case .kbWhisperLarge: "KB-Whisper Large — most accurate"
        case .pianissimo: "Pianissimo — fast Swedish"
        case .roestWhisper: "Røst v3 — no longer available"
        }
    }

    public var summary: String {
        switch self {
        case .appleSpeech:
            "Apple's on-device recognition. Fast, and nothing for Konfer to "
            + "download — macOS installs each language itself."
        case .whisperLargeV3:
            "OpenAI's multilingual Whisper. About 7× real time, 3 GB. Danish, "
            + "Dutch and Polish, and any language Apple does when chosen instead."
        case .kbWhisperSmall:
            "About 40× real time, 485 MB. Much better Swedish than Parakeet."
        case .kbWhisperLarge:
            "About 7× real time, 2.9 GB. The best Swedish available on-device."
        case .pianissimo:
            "Klang AI's Swedish model. About 120× real time, 630 MB. Sixteen "
            + "times faster than KB-Whisper Large, and less tested."
        case .roestWhisper:
            "A Danish fine-tune of Whisper that Konfer no longer uses: stock "
            + "Whisper large-v3 transcribed Danish better."
        }
    }

    /// Why one might pick this model for a language, in a line, beside its
    /// alternative. What large-v3 is the alternative *to* depends on the
    /// language, so the caption does too. Shown under the Model picker, both
    /// on the first-run screen and in the Transcribe sheet.
    public func caption(in language: MeetingLanguage) -> String {
        switch (self, ASRBackendKind(transcribing: language)) {
        case (.appleSpeech, _):
            "Apple's built-in recognition. About nine times faster than "
            + "Whisper, and nothing to download."
        case (.whisperLargeV3, .appleSpeech):
            "OpenAI's multilingual Whisper. About nine times slower than Apple's "
            + "and a 3 GB download, but worth trying where Apple struggles — "
            + "accents, jargon, poor audio."
        case (.kbWhisperLarge, _):
            "The National Library of Sweden's Whisper, trained on 50,000 hours "
            + "of Swedish. The most accurate Swedish here, at about seven times "
            + "real time, and a 2.9 GB download."
        case (.pianissimo, _):
            "Klang AI's Swedish model. Sixteen times faster than KB-Whisper — an "
            + "hour in under a minute — and a 630 MB download, but less tested: "
            + "compare the two on a meeting you know."
        default:
            summary
        }
    }

    /// Rough wall-clock for an hour of audio, for the Settings picker.
    public var estimatedMinutesPerHourOfAudio: Double {
        switch self {
        case .appleSpeech: 1
        case .pianissimo: 0.5
        case .kbWhisperSmall: 2
        case .kbWhisperLarge, .whisperLargeV3, .roestWhisper: 9
        }
    }
}
