//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Trimming is the one feature that makes part of a transcript invisible, so
/// what counts as inside the range — and what an export then contains — is
/// worth pinning down. Nothing here touches audio.
@MainActor
struct TrimmingTests {

    // MARK: - Fixture

    /// Four turns, one per ten seconds, so a range can be drawn between any of
    /// them or straight through one.
    private func makeMeeting(keptRange: KeptRange? = nil) -> Meeting {
        var turns: [Utterance] = []
        for index in 0..<4 {
            let start: TimeInterval = Double(index) * 10
            let middle: TimeInterval = start + 4
            let end: TimeInterval = start + 8
            let speaker: String = index.isMultiple(of: 2) ? "A" : "B"
            turns.append(
                Utterance(
                    speakerId: speaker,
                    start: start,
                    end: end,
                    text: "Turn \(index)",
                    words: [
                        WordSpan(word: "Turn", start: start, end: middle),
                        WordSpan(word: "\(index)", start: middle, end: end)
                    ]
                )
            )
        }
        return Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 40,
            importedAt: Date(),
            language: .swedish,
            speakers: [
                SpeakerLabel(id: "A", name: "Anna"),
                SpeakerLabel(id: "B", name: "Björn")
            ],
            utterances: turns,
            keptRange: keptRange
        )
    }

    // MARK: - What the range keeps

    @Test("An untrimmed meeting keeps every turn")
    func noRangeKeepsEverything() {
        let meeting = makeMeeting()

        #expect(meeting.keptUtterances.count == 4)
        #expect(meeting.trimmedUtterances.before.isEmpty)
        #expect(meeting.trimmedUtterances.after.isEmpty)
    }

    @Test("Turns outside the range are hidden but not deleted")
    func rangeHidesWithoutDeleting() {
        let meeting = makeMeeting(keptRange: KeptRange(start: 9, end: 29))

        #expect(meeting.keptUtterances.map(\.text) == ["Turn 1", "Turn 2"])
        #expect(meeting.trimmedUtterances.before.map(\.text) == ["Turn 0"])
        #expect(meeting.trimmedUtterances.after.map(\.text) == ["Turn 3"])
        // The whole transcript is still on the meeting.
        #expect(meeting.utterances.count == 4)
    }

    @Test("A turn straddling the handle is kept rather than cut mid-sentence")
    func straddlingTurnIsKept() {
        // Turn 1 runs 10–18; the handle lands inside it.
        let meeting = makeMeeting(keptRange: KeptRange(start: 14, end: 40))

        #expect(meeting.keptUtterances.map(\.text).contains("Turn 1"))
        #expect(meeting.trimmedUtterances.before.map(\.text) == ["Turn 0"])
    }

    @Test("Every turn is either kept or trimmed, never both and never neither")
    func keptAndTrimmedPartitionTheTranscript() {
        for start in stride(from: 0.0, through: 35.0, by: 5) {
            let meeting = makeMeeting(keptRange: KeptRange(start: start, end: start + 5))
            let trimmed = meeting.trimmedUtterances
            let total = meeting.keptUtterances.count
                + trimmed.before.count
                + trimmed.after.count

            #expect(total == meeting.utterances.count, "range from \(start)")
        }
    }

    @Test("A range covering the whole recording is stored as no range at all")
    func fullRangeClearsTheTrim() {
        var meeting = makeMeeting()
        meeting.keep(KeptRange(start: 0, end: 40))

        #expect(meeting.keptRange == nil)
    }

    @Test("An empty range is refused rather than hiding the whole transcript")
    func emptyRangeIsRefused() {
        var meeting = makeMeeting()
        meeting.keep(KeptRange(start: 12, end: 12))

        #expect(meeting.keptRange == nil)
        #expect(meeting.keptUtterances.count == 4)
    }

    @Test("Keeping everything restores the hidden turns")
    func keepEverythingRestores() {
        var meeting = makeMeeting(keptRange: KeptRange(start: 9, end: 29))
        meeting.keepEverything()

        #expect(meeting.keptRange == nil)
        #expect(meeting.keptUtterances.count == 4)
    }

    // MARK: - Export

    @Test("Trimmed turns are left out of the Markdown export")
    func markdownExcludesTrimmed() {
        let meeting = makeMeeting(keptRange: KeptRange(start: 9, end: 29))
        let markdown = TranscriptExporter.markdown(for: meeting)

        #expect(markdown.contains("Turn 1"))
        #expect(markdown.contains("Turn 2"))
        #expect(!markdown.contains("Turn 0"))
        #expect(!markdown.contains("Turn 3"))
        // And says so, so a trimmed export doesn't read as the whole meeting.
        #expect(markdown.contains("Trimmed to"))
    }

    @Test("Trimmed turns are left out of the JSON export")
    func jsonExcludesTrimmed() throws {
        let meeting = makeMeeting(keptRange: KeptRange(start: 9, end: 29))
        let data = try TranscriptExporter.data(for: meeting, format: .json)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let transcript = try #require(json["transcript"] as? [[String: Any]])

        #expect(transcript.count == 2)
        #expect(transcript.compactMap { $0["text"] as? String } == ["Turn 1", "Turn 2"])

        let trimmedTo = try #require(json["trimmedTo"] as? [String: Any])
        #expect(trimmedTo["start"] as? Double == 9)
        #expect(trimmedTo["end"] as? Double == 29)
    }

    @Test("An untrimmed export says nothing about trimming")
    func untrimmedExportHasNoRange() throws {
        let meeting = makeMeeting()
        let data = try TranscriptExporter.data(for: meeting, format: .json)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(json["trimmedTo"] == nil)
        #expect(!TranscriptExporter.markdown(for: meeting).contains("Trimmed to"))
    }

    // MARK: - Transcribing a trimmed range

    @Test("Turns from a trimmed extract are put back on the recording's timeline")
    func shiftingMovesTurnsAndWords() {
        let extract = [
            Utterance(
                speakerId: "A",
                start: 0,
                end: 4,
                text: "Hej",
                words: [WordSpan(word: "Hej", start: 0, end: 4)]
            )
        ]

        let shifted = TranscriptionPipeline.shifting(extract, by: 252)

        #expect(shifted[0].start == 252)
        #expect(shifted[0].end == 256)
        #expect(shifted[0].words?.first?.start == 252)
        #expect(shifted[0].words?.first?.end == 256)
        // Identity survives, so a shift can't quietly reshuffle the transcript.
        #expect(shifted[0].id == extract[0].id)
        #expect(shifted[0].text == "Hej")
    }

    @Test("An untrimmed run shifts nothing")
    func shiftingByZeroIsIdentity() {
        let turns = makeMeeting().utterances
        #expect(TranscriptionPipeline.shifting(turns, by: 0) == turns)
    }
}
