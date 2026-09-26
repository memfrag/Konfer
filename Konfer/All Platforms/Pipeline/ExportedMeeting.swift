//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The JSON export, and what ``KonferTranscript`` reads back in.
///
/// Deliberately its own type rather than encoding ``Meeting`` directly: the
/// export is a published format, so it shouldn't drift every time the internal
/// model changes. Voice embeddings are left out — they are large, meaningless
/// outside Konfer, and are biometric data that has no business in a file
/// someone might share.
///
/// Because Konfer reads these files as well as writing them, every field added
/// since the first export is optional, and so is anything whose value a newer
/// Konfer might write that an older one wouldn't recognise — the model, the
/// side a speaker was on. Those are kept as strings and interpreted leniently
/// on import, so a file from a newer version still opens in an older one.
nonisolated struct ExportedMeeting: Codable, Sendable {

    struct Speaker: Codable, Sendable {
        let id: String
        let name: String
        let totalDuration: TimeInterval

        /// Whether someone gave this speaker their name. Absent in files
        /// written before import existed, which is the one thing a generated
        /// "Speaker 2" and a real name can't be told apart by otherwise.
        let named: Bool?

        /// `microphone` or `systemAudio` — in the room or on the call — when
        /// the recording kept the two apart.
        let side: String?
    }

    struct Turn: Codable, Sendable {
        struct Word: Codable, Sendable {
            let word: String
            let start: TimeInterval
            let end: TimeInterval
        }

        let speakerId: String
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let isEdited: Bool
        let words: [Word]?

        /// The turn in the translation language, alongside `text` and never
        /// instead of it. `words` times the words in `text`; swapping the text
        /// underneath them would leave them timing something nobody said.
        /// Absent for a turn that has no translation.
        let translatedText: String?
    }

    struct Translation: Codable, Sendable {
        let from: String
        let to: String
        let translatedAt: Date
    }

    struct Kept: Codable, Sendable {
        let start: TimeInterval
        let end: TimeInterval
    }

    let title: String
    let duration: TimeInterval
    let importedAt: Date
    let language: String
    let degraded: String?

    /// The speech model that made the transcript, as ``ASRBackendKind``'s raw
    /// value. Absent for a meeting older than the record of it.
    let model: String?

    /// Present, and true, only for a transcript made with "Faster, less
    /// complete" — the mark that says speech may be missing.
    let fastTranscribed: Bool?

    /// Present only when the meeting is trimmed. A consumer that ignores it
    /// still gets a coherent transcript — the turns outside are simply absent —
    /// but one that reports timestamps can say what the file covers.
    let trimmedTo: Kept?

    /// Present only when the meeting has been translated, so a consumer
    /// written before translation existed reads exactly what it read before.
    let translation: Translation?

    let speakers: [Speaker]
    let transcript: [Turn]

    init(_ meeting: Meeting) {
        title = meeting.title
        duration = meeting.duration
        importedAt = meeting.importedAt
        language = meeting.language.rawValue
        degraded = meeting.degraded?.rawValue
        model = meeting.transcriptionModel?.rawValue
        fastTranscribed = meeting.wasFastTranscribed == true ? true : nil
        trimmedTo = meeting.keptRange.map { Kept(start: $0.start, end: $0.end) }
        translation = meeting.translation.map {
            Translation(
                from: meeting.language.rawValue,
                to: $0.target.rawValue,
                translatedAt: $0.translatedAt
            )
        }
        speakers = meeting.speakers.map {
            Speaker(
                id: $0.id,
                name: $0.name,
                totalDuration: $0.totalDuration,
                named: $0.isNamed,
                side: $0.side?.rawValue
            )
        }
        transcript = meeting.keptUtterances.map { utterance in
            Turn(
                speakerId: utterance.speakerId,
                speaker: meeting.displayName(for: utterance.speakerId),
                start: utterance.start,
                end: utterance.end,
                text: utterance.text,
                isEdited: utterance.isEdited,
                words: utterance.words?.map {
                    Turn.Word(word: $0.word, start: $0.start, end: $0.end)
                },
                translatedText: meeting.translatedText(for: utterance)
            )
        }
    }
}
