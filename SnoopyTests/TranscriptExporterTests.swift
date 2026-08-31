//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// The clipboard and the Markdown export share one attribution format, so a
/// pasted line and an exported one stay the same shape.
@MainActor
struct TranscriptExporterTests {

    private func utterance(
        speaker: String = "A",
        start: TimeInterval,
        text: String
    ) -> Utterance {
        Utterance(speakerId: speaker, start: start, end: start + 2, text: text)
    }

    private func meeting(_ utterances: [Utterance]) -> Meeting {
        Meeting(
            id: UUID(),
            title: "Kickoff",
            audioPath: "/tmp/kickoff.wav",
            duration: 4000,
            importedAt: Date(),
            language: .swedish,
            speakers: [SpeakerLabel(id: "A", name: "Anna", isNamed: true)],
            utterances: utterances
        )
    }

    @Test("Attribution is a padded timecode and a name")
    func attributionFormat() {
        let line = utterance(start: 754, text: "Full transparens.")

        #expect(
            TranscriptExporter.attribution(for: line, speaker: "Anna")
                == "[00:12:34] Anna:"
        )
    }

    @Test("Attribution pads past an hour rather than rolling over")
    func attributionPastAnHour() {
        let line = utterance(start: 4353, text: "Sent.")

        #expect(
            TranscriptExporter.attribution(for: line, speaker: "Anna")
                == "[01:12:33] Anna:"
        )
    }

    @Test("The plain line is what lands on the clipboard")
    func plainLineJoinsAttributionAndText() {
        let line = utterance(start: 754, text: "Full transparens.")

        #expect(
            TranscriptExporter.plainLine(for: line, speaker: "Anna")
                == "[00:12:34] Anna: Full transparens."
        )
    }

    @Test("Markdown wraps the same attribution in bold")
    func markdownUsesTheSameAttribution() {
        let line = utterance(start: 754, text: "Full transparens.")
        let markdown = TranscriptExporter.markdown(for: meeting([line]))

        #expect(markdown.contains("**[00:12:34] Anna:** Full transparens."))
    }

    @Test("A copied line reflects an edit rather than the original text")
    func plainLineReflectsEdits() {
        var subject = meeting([utterance(start: 754, text: "Full transparens.")])
        subject.editText(of: subject.utterances[0].id, to: "Full transparens, faktiskt.")

        #expect(
            TranscriptExporter.plainLine(for: subject.utterances[0], speaker: "Anna")
                == "[00:12:34] Anna: Full transparens, faktiskt."
        )
    }

    @Test("A degraded run says so in the exported Markdown")
    func degradedRunIsFlaggedInMarkdown() {
        var subject = meeting([utterance(start: 0, text: "Hej.")])
        subject.degraded = .diarization

        #expect(TranscriptExporter.markdown(for: subject).contains("Speaker identification"))
    }
}
