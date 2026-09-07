//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Translated text has no word timings, so the question every one of these
/// tests circles is where a translated cue is allowed to begin and end. The
/// answer, and the whole reason this is honest: only at a time the recogniser
/// produced for the original.
@MainActor
struct TranslatedSubtitleTests {

    // MARK: - Fixtures

    private func words(
        _ text: String,
        from start: TimeInterval,
        each: TimeInterval
    ) -> [WordSpan] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin: TimeInterval = start + Double(index) * each
            return WordSpan(word: String(word), start: begin, end: begin + each)
        }
    }

    private func turn(
        speaker: String = "A",
        text: String,
        from start: TimeInterval,
        each: TimeInterval = 0.4
    ) -> Utterance {
        let spans = words(text, from: start, each: each)
        return Utterance(
            speakerId: speaker,
            start: spans.first?.start ?? start,
            end: spans.last?.end ?? start,
            text: text,
            words: spans
        )
    }

    private func meeting(
        _ utterances: [Utterance],
        translations: [UUID: String] = [:],
        keptRange: KeptRange? = nil
    ) -> Meeting {
        var meeting = Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 600,
            importedAt: Date(),
            language: .swedish,
            speakers: [
                SpeakerLabel(id: "A", name: "Anna"),
                SpeakerLabel(id: "B", name: "Björn")
            ],
            utterances: utterances,
            keptRange: keptRange
        )
        if !translations.isEmpty {
            meeting.translation = TranscriptTranslation(
                target: .english,
                lines: utterances.compactMap { utterance in
                    translations[utterance.id].map {
                        TranslatedLine(utteranceID: utterance.id, text: $0)
                    }
                }
            )
        }
        return meeting
    }

    /// A turn long enough that the 84-character budget cuts it into several
    /// cues, which is the only interesting case.
    private var longTurn: Utterance {
        turn(
            text: "Så om vi tittar på siffrorna från förra året så ser vi att marginalen "
                + "har krympt med ungefär tre procentenheter och det beror dels på "
                + "råvarupriserna och dels på att vi har anställt fler",
            from: 10
        )
    }

    // MARK: - The invariant

    @Test("The translated cues of a turn, rejoined, are exactly the translation")
    func rejoinsToTheTranslation() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))
        let translated = "So if we look at last year's figures we see that the margin has "
            + "shrunk by about three percentage points and that is partly due to raw "
            + "material prices and partly because we have hired more people"

        let out = SubtitleExporter.redistribute(translated, across: source)

        #expect(out.map(\.text).joined(separator: " ") == translated)
    }

    @Test("Nothing is dropped even when the translation is far longer than the original")
    func nothingIsDroppedWhenLonger() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))
        let translated = String(repeating: "verylonggermancompoundword ", count: 40)
            .trimmingCharacters(in: .whitespaces)

        let out = SubtitleExporter.redistribute(translated, across: source)

        #expect(out.map(\.text).joined(separator: " ") == translated)
    }

    // MARK: - Times

    @Test("Every translated cue starts and ends at a time the original used")
    func everyBoundaryIsARealTime() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))
        let starts = Set(source.map(\.start))
        let ends = Set(source.map(\.end))

        let out = SubtitleExporter.redistribute(
            "So if we look at last year's figures the margin has shrunk by three points "
                + "because of raw material prices and because we hired more people",
            across: source
        )

        #expect(out.count > 1)
        for cue in out {
            #expect(starts.contains(cue.start))
            #expect(ends.contains(cue.end))
        }
    }

    @Test("The translated cues span exactly what the original spanned")
    func spansTheSameStretch() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))

        let out = SubtitleExporter.redistribute("A much shorter sentence entirely.", across: source)

        #expect(out.first?.start == source.first?.start)
        #expect(out.last?.end == source.last?.end)
    }

    @Test("Translated cues run in order and never overlap")
    func inOrder() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))

        let out = SubtitleExporter.redistribute(
            "So if we look at the figures from last year we see the margin has shrunk "
                + "by about three percentage points due to raw material prices",
            across: source
        )

        for (earlier, later) in zip(out, out.dropFirst()) {
            #expect(earlier.end <= later.start)
            #expect(earlier.start < earlier.end)
        }
    }

    // MARK: - Cutting

    @Test("Translated cues are cut between words, never inside one")
    func cutsBetweenWords() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))
        let translated = "So if we look at last year's figures we see that the margin "
            + "has shrunk by about three percentage points"
        let vocabulary = Set(translated.split(separator: " ").map(String.init))

        let out = SubtitleExporter.redistribute(translated, across: source)

        for cue in out {
            for word in cue.text.split(separator: " ") {
                #expect(vocabulary.contains(String(word)))
            }
        }
    }

    @Test("A translation shorter than its original fills fewer cues rather than blank ones")
    func shortTranslationFoldsCues() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))

        let out = SubtitleExporter.redistribute("Margins fell.", across: source)

        #expect(source.count > 1)
        #expect(out.count < source.count)
        #expect(out.allSatisfy { !$0.text.isEmpty })
        #expect(out.map(\.text).joined(separator: " ") == "Margins fell.")
    }

    @Test("A turn with no word timings is one cue in the translation as it is in the original")
    func untimedTurnStaysOneCue() {
        var edited = longTurn
        edited.words = nil
        edited.isEdited = true
        let source = SubtitleExporter.cues(for: meeting([edited]))

        let out = SubtitleExporter.redistribute("A translation of the whole thing.", across: source)

        #expect(source.count == 1)
        #expect(out.count == 1)
        #expect(out[0].start == source[0].start)
        #expect(out[0].end == source[0].end)
        #expect(out[0].text == "A translation of the whole thing.")
    }

    // MARK: - Attribution

    @Test("Only the first cue of a translated turn carries the speaker's name")
    func onlyTheFirstCueIsAttributed() {
        let source = SubtitleExporter.cues(for: meeting([longTurn]))

        let out = SubtitleExporter.redistribute(
            "So if we look at last year's figures we see that the margin has shrunk "
                + "by about three percentage points because of raw material prices",
            across: source
        )

        #expect(out.first?.speaker == "Anna")
        #expect(out.dropFirst().allSatisfy { $0.speaker == nil })
    }

    // MARK: - Through the exporter

    @Test("A turn with no translation goes out in the original language rather than blank")
    func untranslatedTurnKeepsItsOriginal() {
        let first = turn(speaker: "A", text: "Hej allihopa och välkomna.", from: 0)
        let second = turn(speaker: "B", text: "Tack, då sätter vi igång.", from: 5)
        let meeting = meeting(
            [first, second],
            translations: [first.id: "Hello everyone and welcome."]
        )

        let out = SubtitleExporter.cues(for: meeting, rendering: .translated)

        #expect(out.contains { $0.text == "Hello everyone and welcome." })
        #expect(out.contains { $0.text == "Tack, då sätter vi igång." })
    }

    @Test("The original rendering is untouched by a translation being present")
    func originalRenderingIsUnchanged() {
        let only = turn(text: "Hej allihopa och välkomna.", from: 0)
        let translated = meeting([only], translations: [only.id: "Hello everyone and welcome."])
        let plain = meeting([only])

        #expect(SubtitleExporter.cues(for: translated) == SubtitleExporter.cues(for: plain))
    }

    @Test("A translated export stops at the trim, like every other export")
    func trimApplies() {
        let first = turn(speaker: "A", text: "Hej allihopa och välkomna.", from: 0)
        let second = turn(speaker: "B", text: "Tack, då sätter vi igång.", from: 30)
        let meeting = meeting(
            [first, second],
            translations: [first.id: "Hello everyone.", second.id: "Thanks, let's begin."],
            keptRange: KeptRange(start: 20, end: 60)
        )

        let out = SubtitleExporter.cues(for: meeting, rendering: .translated)

        #expect(out.count == 1)
        #expect(out[0].text == "Thanks, let's begin.")
    }

    @Test("Translated SubRip numbers its cues from one, like the original")
    func srtNumbering() {
        let only = turn(text: "Hej allihopa och välkomna.", from: 0)
        let meeting = meeting([only], translations: [only.id: "Hello everyone and welcome."])

        let srt = SubtitleExporter.srt(for: meeting, rendering: .translated)

        #expect(srt.hasPrefix("1\n"))
        #expect(srt.contains("Anna: Hello everyone and welcome."))
    }

    @Test("Translated WebVTT puts the speaker in a voice tag, as the original does")
    func webVTTVoiceTag() {
        let only = turn(text: "Hej allihopa och välkomna.", from: 0)
        let meeting = meeting([only], translations: [only.id: "Hello everyone and welcome."])

        let vtt = SubtitleExporter.webVTT(for: meeting, rendering: .translated)

        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("<v Anna>Hello everyone and welcome."))
    }
}
