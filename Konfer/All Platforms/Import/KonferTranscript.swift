//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A transcript Konfer exported as JSON, on its way back in.
///
/// Unlike a Klang file this one already is a meeting, give or take: speakers
/// and their names, turns with word timings, hand edits, the translation, the
/// trim. So nothing is regrouped or re-derived — the turns come back exactly
/// as they were cut — and the only questions the import sheet asks are the
/// ones the file can't answer: which folder, and, later, where the recording is.
///
/// What doesn't survive is what the export leaves out on purpose. The recording
/// isn't in the file, so the meeting opens unplayable until pointed at it. Voice
/// embeddings aren't either, so imported speakers can't be matched against
/// People or teach it anything. And a trimmed meeting's export holds only what
/// was kept, so the trim comes back but the lines outside it are gone.
nonisolated struct KonferTranscript: Sendable {

    let file: ExportedMeeting
    let language: MeetingLanguage

    var title: String { file.title }
    var duration: TimeInterval { file.duration }
    var speakerCount: Int { file.speakers.count }

    /// The language the translation is in, when there is one Konfer knows.
    var translationTarget: MeetingLanguage? {
        file.translation.flatMap { MeetingLanguage(rawValue: $0.to) }
    }
}

// MARK: - Reading

nonisolated extension KonferTranscript {

    /// Decodes a Konfer export, or returns nil when the data isn't one, so
    /// the caller can try the next format.
    ///
    /// A file that *is* a Konfer export but can't become a meeting throws
    /// instead: saying "this isn't a transcript" about the user's own export
    /// would send them looking for the wrong problem.
    static func decode(_ data: Data, from url: URL) throws -> KonferTranscript? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ExportedMeeting.self, from: data) else {
            return nil
        }

        // Not the lenient decoding the library uses for `"auto"`: no export
        // was ever written with it, and guessing Swedish for a language this
        // version doesn't know would file the transcript under the wrong one.
        guard let language = MeetingLanguage(rawValue: file.language) else {
            throw TranscriptImportError.unrecognizedFormat(url)
        }
        guard file.transcript.contains(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw TranscriptImportError.noSpeech(url)
        }

        return KonferTranscript(file: file, language: language)
    }
}

// MARK: - Import

nonisolated extension KonferTranscript {

    /// The meeting the file describes, under a new id and with no recording.
    ///
    /// A new id rather than any kept one — the export carries none, and a
    /// meeting imported beside the one it was exported from must not share it.
    /// Turn ids are new for the same reason, which is why the translation is
    /// rebuilt from each turn's `translatedText` rather than copied.
    func meeting() -> Meeting {

        let utterances = file.transcript.map { turn in
            Utterance(
                speakerId: turn.speakerId,
                start: turn.start,
                end: turn.end,
                text: turn.text,
                // An edited turn has no timings left to import, and a stray
                // array beside one would describe words that were replaced.
                words: turn.isEdited ? nil : turn.words?.map {
                    WordSpan(word: $0.word, start: $0.start, end: $0.end)
                },
                isEdited: turn.isEdited
            )
        }

        return Meeting(
            id: UUID(),
            title: file.title,
            // `audioExists` reads false for an empty path, so the meeting opens
            // with the missing-recording notice and its "Choose Recording…".
            audioPath: "",
            duration: file.duration,
            importedAt: file.importedAt,
            language: language,
            speakers: roster,
            utterances: utterances,
            degraded: file.degraded.flatMap(DegradedStage.init(rawValue:)),
            sliceCuts: nil,
            keptRange: file.trimmedTo.map { KeptRange(start: $0.start, end: $0.end) },
            wasFastTranscribed: file.fastTranscribed,
            translation: translation(of: utterances),
            transcriptionModel: file.model.flatMap(ASRBackendKind.init(rawValue:))
        )
    }

    /// The speakers as exported, plus any a turn names that the roster
    /// doesn't — a file edited by hand, most likely — so that no turn points
    /// at a speaker the meeting has never heard of.
    private var roster: [SpeakerLabel] {
        var labels = file.speakers.map { speaker in
            SpeakerLabel(
                id: speaker.id,
                name: speaker.name,
                isNamed: speaker.named ?? Self.looksNamed(speaker),
                embedding: [],
                totalDuration: speaker.totalDuration,
                side: speaker.side.flatMap(RecordingSide.init(rawValue:))
            )
        }
        var known = Set(labels.map(\.id))
        for turn in file.transcript where known.insert(turn.speakerId).inserted {
            labels.append(SpeakerLabel(id: turn.speakerId, name: turn.speaker))
        }
        return labels
    }

    /// For exports older than the `named` field: a name the pipeline hands
    /// out is a placeholder, anything else someone typed.
    private static func looksNamed(_ speaker: ExportedMeeting.Speaker) -> Bool {
        if speaker.id == SpeakerLabel.unknownID || speaker.name == SpeakerLabel.unknown.name {
            return false
        }
        return speaker.name.wholeMatch(of: /Speaker \d+/) == nil
    }

    /// The translation keyed to the new turns, or nil when there is none or
    /// it is into a language this version doesn't know.
    private func translation(of utterances: [Utterance]) -> TranscriptTranslation? {
        guard let exported = file.translation, let target = translationTarget else {
            return nil
        }
        let lines = zip(file.transcript, utterances).compactMap { turn, utterance in
            turn.translatedText.map { TranslatedLine(utteranceID: utterance.id, text: $0) }
        }
        return TranscriptTranslation(
            target: target,
            lines: lines,
            translatedAt: exported.translatedAt
        )
    }
}
