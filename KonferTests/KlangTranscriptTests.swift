//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Importing a Klang export is the one path into the library that produces a
/// transcript nothing in Konfer heard, so what it produces is worth pinning
/// down. Fixtures only — no files beyond the temporary ones written here.
struct KlangTranscriptTests {

    // MARK: - Fixtures

    private func json(_ texts: String) -> Data {
        Data("{\"texts\":[\(texts)]}".utf8)
    }

    private func span(
        _ text: String,
        _ start: Double,
        _ end: Double,
        _ speaker: String
    ) -> String {
        """
        {"text":"\(text)","start":\(start),"end":\(end),"speaker":"\(speaker)"}
        """
    }

    /// `read` only takes a URL, since that is all the importer ever has.
    private func read(_ data: Data) throws -> KlangTranscript {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try KlangTranscript.read(contentsOf: url)
    }

    // MARK: - Reading

    @Test("A Klang export decodes into its spans")
    func decodesSpans() throws {
        let transcript = try read(json([
            span("Hej allihopa.", 0.18, 3.18, "Talare 1"),
            span("Hej.", 3.76, 5.2, "Talare 2")
        ].joined(separator: ",")))

        #expect(transcript.segments.count == 2)
        #expect(transcript.segments[0].text == "Hej allihopa.")
        #expect(transcript.segments[0].speaker == "Talare 1")
        #expect(transcript.duration == 5.2)
        #expect(transcript.speakerIDs == ["Talare 1", "Talare 2"])
    }

    @Test("JSON that isn't a Klang export is rejected rather than half-read")
    func rejectsOtherJSON() throws {
        #expect(throws: TranscriptImportError.self) {
            try read(Data(#"{"segments":[{"text":"Hej"}]}"#.utf8))
        }
    }

    @Test("A transcript with nothing said in it is rejected")
    func rejectsEmptyTranscript() throws {
        #expect(throws: TranscriptImportError.self) {
            try read(json(span("   ", 0, 1, "Talare 1")))
        }
    }

    @Test("Spans out of order are put back in time order")
    func sortsSpans() throws {
        let transcript = try read(json([
            span("Andra.", 5.0, 6.0, "Talare 1"),
            span("Första.", 1.0, 2.0, "Talare 1")
        ].joined(separator: ",")))

        #expect(transcript.segments.map(\.text) == ["Första.", "Andra."])
    }

    @Test("A span that ends before it starts is repaired rather than dropped")
    func repairsReversedSpan() throws {
        let transcript = try read(json(span("Bakvänt.", 4.0, 2.0, "Talare 1")))

        #expect(transcript.segments[0].start == 2.0)
        #expect(transcript.segments[0].end == 4.0)
    }

    @Test("A span with no speaker joins the unknown speaker")
    func unattributedSpanFallsBackToUnknown() throws {
        let transcript = try read(json(span("Vem sa det?", 0, 1, "")))
        let meeting = transcript.meeting(title: "Möte", language: .swedish)

        #expect(transcript.segments[0].speaker == SpeakerLabel.unknownID)
        #expect(meeting.speakers.map(\.name) == [SpeakerLabel.unknown.name])
    }

    // MARK: - The meeting

    @Test("Consecutive spans from one speaker become a single turn")
    func groupsSpansIntoTurns() throws {
        let transcript = try read(json([
            span("Att vi, det är helt rätt,", 0.18, 3.18, "Talare 1"),
            span("vi vill ha information.", 3.76, 8.52, "Talare 1"),
            span("Precis.", 9.0, 10.0, "Talare 2")
        ].joined(separator: ",")))

        let meeting = transcript.meeting(title: "Möte", language: .swedish)

        #expect(meeting.utterances.count == 2)
        #expect(meeting.utterances[0].speakerId == "Talare 1")
        #expect(meeting.utterances[0].text
            == "Att vi, det är helt rätt, vi vill ha information.")
        #expect(meeting.utterances[0].start == 0.18)
        #expect(meeting.utterances[0].end == 8.52)
        #expect(meeting.utterances[1].speakerId == "Talare 2")
    }

    @Test("A silence longer than a turn's worth cuts the turn in two")
    func longSilenceStartsANewTurn() throws {
        let gap = SpeakerAligner.turnGapThreshold + 1
        let transcript = try read(json([
            span("Först.", 0, 1, "Talare 1"),
            span("Sedan.", 1 + gap, 2 + gap, "Talare 1")
        ].joined(separator: ",")))

        #expect(transcript.meeting(title: "Möte", language: .swedish).utterances.count == 2)
    }

    @Test("Each Klang span survives as one entry in the turn's word timings")
    func spansBecomeWordTimings() throws {
        let transcript = try read(json([
            span("Först.", 0.0, 1.0, "Talare 1"),
            span("Sedan.", 1.2, 2.0, "Talare 1")
        ].joined(separator: ",")))

        let turn = try #require(
            transcript.meeting(title: "Möte", language: .swedish).utterances.first
        )
        let words = try #require(turn.words)

        #expect(words.count == 2)
        #expect(words[0] == WordSpan(word: "Först.", start: 0.0, end: 1.0))
        #expect(words[1] == WordSpan(word: "Sedan.", start: 1.2, end: 2.0))
        #expect(turn.isEdited == false)
    }

    @Test("Speakers keep Klang's own labels, unnamed and without a voiceprint")
    func rosterKeepsKlangLabels() throws {
        let transcript = try read(json([
            span("Ett.", 0, 2, "Talare 1"),
            span("Två.", 2, 5, "Talare 2"),
            span("Tre.", 5, 6, "Talare 1")
        ].joined(separator: ",")))

        let meeting = transcript.meeting(title: "Möte", language: .swedish)

        #expect(meeting.speakers.map(\.id) == ["Talare 1", "Talare 2"])
        #expect(meeting.speakers.allSatisfy { $0.name == $0.id })
        #expect(meeting.speakers.allSatisfy { !$0.isNamed })
        // No voice data in the file, so nothing to match against the
        // enrollment roster or add to it.
        #expect(meeting.speakers.allSatisfy { $0.embedding.isEmpty })
        #expect(meeting.speakers[0].totalDuration == 3)
        #expect(meeting.speakers[1].totalDuration == 3)
    }

    @Test("An imported meeting has no recording and says so")
    func importedMeetingHasNoAudio() throws {
        let transcript = try read(json(span("Hej.", 0, 1, "Talare 1")))
        let meeting = transcript.meeting(title: "Möte", language: .swedish)

        #expect(meeting.audioPath.isEmpty)
        #expect(meeting.audioExists == false)
        #expect(meeting.duration == 1)
        #expect(meeting.degraded == nil)
        #expect(meeting.title == "Möte")
        #expect(meeting.language == .swedish)
    }

    // MARK: - Attaching a recording afterwards

    @Test("Attaching a recording gives the meeting its path and the file's length")
    func attachingAudioTakesTheFilesDuration() throws {
        let transcript = try read(json(span("Hej.", 0, 1, "Talare 1")))
        var meeting = transcript.meeting(title: "Möte", language: .swedish)

        meeting.attachAudio(at: URL(fileURLWithPath: "/tmp/mote.m4a"), duration: 90)

        #expect(meeting.audioPath == "/tmp/mote.m4a")
        #expect(meeting.duration == 90)
    }

    @Test("A recording whose length couldn't be read leaves the transcript's own")
    func attachingAudioKeepsDurationWhenUnknown() throws {
        let transcript = try read(json(span("Hej.", 0, 1, "Talare 1")))
        var meeting = transcript.meeting(title: "Möte", language: .swedish)

        meeting.attachAudio(at: URL(fileURLWithPath: "/tmp/mote.m4a"), duration: nil)

        #expect(meeting.duration == 1)
    }
}
