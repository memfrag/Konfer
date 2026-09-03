//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

// MARK: - KlangTranscript

/// A transcript exported by the Klang app.
///
/// The file is one object with a single `texts` array of sentence-sized spans,
/// each carrying its own start, end and speaker label:
///
/// ```json
/// { "texts": [ { "text": "…", "start": 0.18, "end": 3.18, "speaker": "Talare 1" } ] }
/// ```
///
/// Both halves Konfer's pipeline spends its minutes producing are already in
/// there — who spoke when, and what was said — so importing one runs no models
/// at all and finishes instantly. What is *not* in there is word timings and
/// the recording itself: the first is why whole spans stand in for words in
/// ``meeting(title:language:)``, and the second is why an imported meeting
/// opens unplayable until someone points it at the audio (see
/// ``Meeting/attachAudio(at:duration:)``).
nonisolated struct KlangTranscript: Sendable {

    /// One span of speech as Klang wrote it: roughly a sentence, never a whole
    /// speaker turn — half an hour of talk arrives as some four hundred of them.
    struct Segment: Sendable, Equatable {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        /// Klang's own generated label, e.g. "Talare 1". Anonymous, and the
        /// only speaker information the file carries.
        let speaker: String
    }

    /// Non-empty, in time order, with any reversed span repaired.
    let segments: [Segment]

    /// Where the last person stopped talking — not the length of the
    /// recording, which the file doesn't say.
    var duration: TimeInterval { segments.map(\.end).max() ?? 0 }

    /// The speakers, in the order they first speak.
    var speakerIDs: [String] {
        var seen: Set<String> = []
        return segments.map(\.speaker).filter { seen.insert($0).inserted }
    }
}

// MARK: - Reading

nonisolated extension KlangTranscript {

    /// The file exactly as written, before any tidying.
    private struct File: Decodable {
        struct Text: Decodable {
            let text: String
            let start: TimeInterval
            let end: TimeInterval
            let speaker: String
        }
        let texts: [Text]
    }

    /// Decodes a Klang export, rejecting anything that isn't one.
    ///
    /// Klang's own files come ordered, non-overlapping and complete. The
    /// tidying below is for the one that has been through somebody's editor on
    /// the way here: an out-of-order span would put the transcript out of
    /// sequence, and a reversed one would describe a turn that ends before it
    /// starts.
    static func read(contentsOf url: URL) throws -> KlangTranscript {

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TranscriptImportError.unreadable(url, underlying: error)
        }

        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            throw TranscriptImportError.unrecognizedFormat(url)
        }

        let usable = file.texts
            .map { text -> Segment in
                let speaker = text.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
                return Segment(
                    text: text.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    start: min(text.start, text.end),
                    end: max(text.start, text.end),
                    // A span Klang couldn't attribute lands in the same bucket
                    // a degraded run uses, rather than under a blank name.
                    speaker: speaker.isEmpty ? SpeakerLabel.unknownID : speaker
                )
            }
            .filter { !$0.text.isEmpty }

        // Sorting by start alone would be free to reorder spans that share
        // one, and Swift's sort is not stable. Falling back to the file's own
        // order keeps a re-import of the same file identical to the first.
        let segments = usable.enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map(\.element)

        guard !segments.isEmpty else { throw TranscriptImportError.noSpeech(url) }

        return KlangTranscript(segments: segments)
    }
}

// MARK: - Import

nonisolated extension KlangTranscript {

    /// Assembles the meeting this transcript describes.
    ///
    /// The grouping goes *through* ``SpeakerAligner`` rather than around it, by
    /// handing it the file's own spans as both halves of the merge: one word
    /// per span, one speaker segment per span. Attribution is then trivially
    /// exact — every span overlaps precisely the segment it came from — and
    /// only the turn-cutting rules do any work, so an imported transcript
    /// breaks into paragraphs on the same terms as one Konfer transcribed
    /// itself instead of on a second set of thresholds free to drift from the
    /// first. It also matters that it groups at all: Klang writes about a
    /// sentence at a time, and a transcript of four hundred rows, each with its
    /// own speaker chip and timestamp, is not one anybody reads.
    ///
    /// A Klang span survives as one entry in ``Utterance/words``. Those entries
    /// are sentences rather than words, which is as fine as this file's timing
    /// gets — nothing in it was ever timed word by word. Everything reading
    /// that array then degrades to sentence granularity rather than switching
    /// off: playback highlights the sentence being spoken, clicking one seeks
    /// to it, and a turn can still be split where the speaker actually changed.
    func meeting(title: String, language: MeetingLanguage) -> Meeting {

        let spans = segments.map {
            WordSpan(word: $0.text, start: $0.start, end: $0.end)
        }
        let speakerSegments = segments.map {
            TimedSpeakerSegment(
                speakerId: $0.speaker,
                embedding: [],
                startTimeSeconds: Float($0.start),
                endTimeSeconds: Float($0.end),
                qualityScore: 1
            )
        }

        return Meeting(
            id: UUID(),
            title: title,
            // Klang's export neither carries the recording nor names it, and
            // there is nothing to guess from. `audioExists` reads false for an
            // empty path, so the meeting opens with the missing-recording
            // notice and its "Choose Recording…" button.
            audioPath: "",
            duration: duration,
            importedAt: Date(),
            language: language,
            speakers: roster,
            utterances: SpeakerAligner.align(words: spans, segments: speakerSegments),
            degraded: nil,
            sliceCuts: nil,
            wasFastTranscribed: nil
        )
    }

    /// The meeting's speaker roster, in the order the speakers first talk.
    ///
    /// Klang's labels are kept as written rather than renumbered into Konfer's
    /// "Speaker 1": they are what the user has already been reading in the
    /// other app, and renaming one costs the same click either way. They stay
    /// marked unnamed, because "Talare 2" is a placeholder in any language.
    ///
    /// The embeddings are empty and stay empty — the file carries no voice
    /// data — so an imported meeting can neither be matched against the
    /// enrollment roster nor contribute to it. Both
    /// ``SpeakerStore/suggestion(for:)`` and ``SpeakerStore/enroll(name:embedding:)``
    /// already refuse an empty embedding, so naming a speaker here stays local
    /// to this meeting rather than teaching Konfer a voice it never heard.
    private var roster: [SpeakerLabel] {

        var spoken: [String: TimeInterval] = [:]
        for segment in segments {
            spoken[segment.speaker, default: 0] += max(0, segment.end - segment.start)
        }

        return speakerIDs.map { id in
            SpeakerLabel(
                id: id,
                name: id == SpeakerLabel.unknownID ? SpeakerLabel.unknown.name : id,
                isNamed: false,
                embedding: [],
                totalDuration: spoken[id] ?? 0
            )
        }
    }
}
