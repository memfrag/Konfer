//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - WordSpan

/// A single word with the time span it occupies in the recording.
///
/// Word spans come from the ASR model's token timings. They drive word-level
/// highlighting during playback and are the anchor points used when an
/// utterance is split. They are dropped for an utterance whose text has been
/// edited, because the edited words no longer correspond to anything the model
/// actually heard.
///
nonisolated struct WordSpan: Codable, Hashable, Sendable {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}

// MARK: - Utterance

/// One speaker turn: a contiguous run of words attributed to a single speaker.
///
/// `speakerId` refers to an entry in the owning ``Meeting``'s speaker roster
/// rather than carrying a name directly. That indirection is what makes
/// "rename once, relabel everywhere" and cluster merging trivial.
///
nonisolated struct Utterance: Identifiable, Codable, Hashable, Sendable {

    let id: UUID

    /// Roster key. Mutable, because reassignment and merges rewrite it.
    var speakerId: String

    let start: TimeInterval
    let end: TimeInterval

    var text: String

    /// Word-level timings, or `nil` once the text has been edited.
    var words: [WordSpan]?

    /// Whether the text has been edited by hand since transcription.
    var isEdited: Bool

    init(
        id: UUID = UUID(),
        speakerId: String,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        words: [WordSpan]? = nil,
        isEdited: Bool = false
    ) {
        self.id = id
        self.speakerId = speakerId
        self.start = start
        self.end = end
        self.text = text
        self.words = words
        self.isEdited = isEdited
    }

    var duration: TimeInterval { max(0, end - start) }
}

// MARK: - SpeakerLabel

/// One speaker within a meeting.
///
/// The diarizer only ever produces anonymous cluster ids. A label carries the
/// display name, the mean voice embedding used for cross-meeting matching, and
/// any pending enrollment suggestion.
///
nonisolated struct SpeakerLabel: Identifiable, Codable, Hashable, Sendable {

    /// The diarizer's cluster id, e.g. "Speaker 1". Stable within a meeting.
    let id: String

    /// What the user sees. Defaults to a generated anonymous name.
    var name: String

    /// True once the user has named this speaker, as opposed to accepting the
    /// generated default. Distinguishes "Anna" from "Speaker 2".
    var isNamed: Bool

    /// Duration-weighted mean of the cluster's segment embeddings, used to
    /// match this speaker against the enrollment roster in later meetings.
    var embedding: [Float]

    /// Total time attributed to this speaker, in seconds.
    var totalDuration: TimeInterval

    /// A pending "Sounds like Anna?" suggestion from the enrollment store.
    /// Suggestions are never applied automatically — see ``SpeakerStore``.
    var suggestion: EnrollmentSuggestion?

    init(
        id: String,
        name: String,
        isNamed: Bool = false,
        embedding: [Float] = [],
        totalDuration: TimeInterval = 0,
        suggestion: EnrollmentSuggestion? = nil
    ) {
        self.id = id
        self.name = name
        self.isNamed = isNamed
        self.embedding = embedding
        self.totalDuration = totalDuration
        self.suggestion = suggestion
    }
}

/// A proposed match between a meeting speaker and an enrolled profile.
nonisolated struct EnrollmentSuggestion: Codable, Hashable, Sendable {
    let profileID: UUID
    let name: String
    /// Cosine distance to the enrolled profile. Lower is a closer match.
    let distance: Float
}

// MARK: - MeetingLanguage

/// The language the user declared for a recording.
///
/// This decides which model runs — see ``ASRBackendKind/init(transcribing:)``.
/// It also pins Whisper's own language, without which it detects one per chunk
/// and flips mid-recording on Swedish speech containing English terms.
///
/// It is the only such choice the user makes: the model follows from it, so
/// there is nothing else to get wrong. A wrong language, though, doesn't
/// degrade an hour of transcript so much as replace it with something else.
///
/// Declaration order is picker order: the two Snoopy was built for, then the
/// three it grew for, then the ones Apple happened to already cover.
public nonisolated enum MeetingLanguage: String, Codable, CaseIterable, Sendable {
    case english
    case swedish
    case danish
    case dutch
    case polish
    case german
    case spanish
    case french
    case italian
    case portuguese

    public var displayName: String {
        switch self {
        case .english: "English"
        case .swedish: "Swedish"
        case .danish: "Danish"
        case .dutch: "Dutch"
        case .polish: "Polish"
        case .german: "German"
        case .spanish: "Spanish"
        case .french: "French"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        }
    }

    /// The BCP-47 language code, for matching against Apple's supported locales
    /// and for pinning Whisper.
    public var code: String {
        switch self {
        case .english: "en"
        case .swedish: "sv"
        case .danish: "da"
        case .dutch: "nl"
        case .polish: "pl"
        case .german: "de"
        case .spanish: "es"
        case .french: "fr"
        case .italian: "it"
        case .portuguese: "pt"
        }
    }

    /// The region to fall back to when the user's own doesn't have a variant of
    /// this language, e.g. a Swedish user transcribing German gets `de-DE`.
    public var homeRegion: String {
        switch self {
        case .english: "US"
        case .swedish: "SE"
        case .danish: "DK"
        case .dutch: "NL"
        case .polish: "PL"
        case .german: "DE"
        case .spanish: "ES"
        case .french: "FR"
        case .italian: "IT"
        case .portuguese: "PT"
        }
    }

    /// Meetings written before the automatic option was removed say `"auto"`,
    /// which always resolved to Swedish: it never reached Apple's transcriber,
    /// and Whisper was pinned to `sv` for it. Decoding it as anything else
    /// would relabel those transcripts; failing to decode it would drop them
    /// from the library entirely, since ``MeetingStore`` skips what it cannot
    /// read.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MeetingLanguage(rawValue: raw) ?? .swedish
    }
}

// MARK: - DegradedStage

/// Records that a run completed with one stage missing.
nonisolated enum DegradedStage: String, Codable, Sendable {
    /// Diarization failed or found no speakers; everything is attributed to a
    /// single unknown speaker.
    case diarization
}

// MARK: - Meeting

/// A transcribed recording, as persisted in the library.
nonisolated struct Meeting: Identifiable, Codable, Hashable, Sendable {

    /// Bump when the on-disk shape changes.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = Meeting.currentSchemaVersion

    let id: UUID
    var title: String

    /// Where the audio lives. Not copied into the app — the file stays where
    /// the user put it, and may later be moved or deleted.
    var audioPath: String

    var duration: TimeInterval
    var importedAt: Date
    var language: MeetingLanguage

    var speakers: [SpeakerLabel]
    var utterances: [Utterance]

    /// Set when a stage failed but the run was still worth keeping.
    var degraded: DegradedStage?

    /// Where the recording was cut for parallel transcription, shown as ticks
    /// under the player. Optional so earlier meetings still decode.
    var sliceCuts: [TimeInterval]?

    /// Set when this transcript was produced with fast (chunked) transcription,
    /// which is known to drop speech. Optional so meetings written before the
    /// setting existed still decode.
    var wasFastTranscribed: Bool?

    var audioURL: URL { URL(fileURLWithPath: audioPath) }

    /// Whether the source recording is still where we left it. Checked when a
    /// meeting is opened rather than swept at launch.
    var audioExists: Bool { FileManager.default.fileExists(atPath: audioPath) }

    func speaker(_ id: String) -> SpeakerLabel? {
        speakers.first { $0.id == id }
    }

    func displayName(for speakerId: String) -> String {
        speaker(speakerId)?.name ?? speakerId
    }
}

// MARK: - Unknown speaker

nonisolated extension SpeakerLabel {
    /// The single bucket used when diarization produced nothing usable.
    static let unknownID = "unknown"

    static var unknown: SpeakerLabel {
        SpeakerLabel(id: unknownID, name: "Unknown speaker", isNamed: false)
    }
}
