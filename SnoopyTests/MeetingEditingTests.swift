//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// The transcript is editable, and the rule that matters is when word timings
/// survive: they must be dropped exactly where the text changed, and nowhere
/// else, or playback highlighting silently starts lying.
@MainActor
struct MeetingEditingTests {

    // MARK: - Fixture

    private func makeMeeting() -> Meeting {
        let first = Utterance(
            speakerId: "A",
            start: 0,
            end: 2,
            text: "Hej allihopa.",
            words: [
                WordSpan(word: "Hej", start: 0, end: 0.5),
                WordSpan(word: "allihopa.", start: 0.6, end: 2.0)
            ]
        )
        let second = Utterance(
            speakerId: "B",
            start: 3,
            end: 5,
            text: "Good morning.",
            words: [
                WordSpan(word: "Good", start: 3.0, end: 3.5),
                WordSpan(word: "morning.", start: 3.6, end: 5.0)
            ]
        )
        return Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 6,
            importedAt: Date(),
            language: .auto,
            speakers: [
                SpeakerLabel(id: "A", name: "Speaker 1", embedding: [1, 0], totalDuration: 2),
                SpeakerLabel(id: "B", name: "Speaker 2", embedding: [0, 1], totalDuration: 2)
            ],
            utterances: [first, second]
        )
    }

    // MARK: - Renaming

    @Test("Renaming a speaker relabels every one of their lines at once")
    func renameAppliesEverywhere() {
        var meeting = makeMeeting()
        meeting.renameSpeaker("A", to: "Anna")

        #expect(meeting.displayName(for: "A") == "Anna")
        #expect(meeting.speaker("A")?.isNamed == true)
        #expect(meeting.utterances[0].speakerId == "A")
    }

    @Test("Renaming clears any pending enrollment suggestion")
    func renameClearsSuggestion() {
        var meeting = makeMeeting()
        meeting.speakers[0].suggestion = EnrollmentSuggestion(
            profileID: UUID(), name: "Björn", distance: 0.2
        )

        meeting.renameSpeaker("A", to: "Anna")

        #expect(meeting.speaker("A")?.suggestion == nil)
    }

    // MARK: - Merging

    @Test("Merging two clusters rewrites every line and drops the absorbed one")
    func mergeRewritesUtterances() {
        var meeting = makeMeeting()
        meeting.mergeSpeaker("B", into: "A")

        #expect(meeting.speakers.count == 1)
        #expect(meeting.speakers[0].id == "A")
        #expect(meeting.utterances.allSatisfy { $0.speakerId == "A" })
        #expect(meeting.speaker("A")?.totalDuration == 4)
    }

    @Test("Merging a speaker into itself does nothing")
    func mergeIntoSelfIsANoOp() {
        var meeting = makeMeeting()
        meeting.mergeSpeaker("A", into: "A")

        #expect(meeting.speakers.count == 2)
    }

    // MARK: - Reassignment

    @Test("Reassigning moves one line without touching the rest")
    func reassignMovesOneLine() {
        var meeting = makeMeeting()
        meeting.reassign(meeting.utterances[0].id, to: "B")

        #expect(meeting.utterances[0].speakerId == "B")
        #expect(meeting.utterances[1].speakerId == "B")
        #expect(meeting.speakers.count == 2)
    }

    @Test("Reassigning to a speaker who isn't in the meeting is refused")
    func reassignToUnknownSpeakerIsRefused() {
        var meeting = makeMeeting()
        meeting.reassign(meeting.utterances[0].id, to: "Z")

        #expect(meeting.utterances[0].speakerId == "A")
    }

    // MARK: - Splitting

    @Test("Splitting divides a turn at a word boundary and keeps both halves' timings")
    func splitDividesAtWordBoundary() {
        var meeting = makeMeeting()
        let original = meeting.utterances[0]

        let newID = meeting.splitUtterance(original.id, atWordIndex: 1)

        #expect(newID != nil)
        #expect(meeting.utterances.count == 3)
        #expect(meeting.utterances[0].text == "Hej")
        #expect(meeting.utterances[0].end == 0.5)
        #expect(meeting.utterances[1].text == "allihopa.")
        #expect(meeting.utterances[1].start == 0.6)
        #expect(meeting.utterances[1].words?.count == 1)
        // The second half stays with the same speaker until it's reassigned.
        #expect(meeting.utterances[1].speakerId == "A")
    }

    @Test("Splitting at the edges is refused — it would produce an empty half")
    func splitAtEdgesIsRefused() {
        var meeting = makeMeeting()
        let id = meeting.utterances[0].id

        #expect(meeting.splitUtterance(id, atWordIndex: 0) == nil)
        #expect(meeting.splitUtterance(id, atWordIndex: 2) == nil)
        #expect(meeting.utterances.count == 2)
    }

    @Test("An edited turn can't be split — its words are no longer real timings")
    func splitRefusedAfterEditing() {
        var meeting = makeMeeting()
        let id = meeting.utterances[0].id
        meeting.editText(of: id, to: "Hej på er allihopa.")

        #expect(meeting.splitUtterance(id, atWordIndex: 1) == nil)
    }

    // MARK: - Merging turns

    @Test("Merging with the next turn joins text, spans, and word timings")
    func mergeWithNextJoinsBothTurns() {
        var meeting = makeMeeting()
        let firstID = meeting.utterances[0].id

        let survivor = meeting.mergeUtterance(firstID, with: .next)

        #expect(survivor == firstID)
        #expect(meeting.utterances.count == 1)
        #expect(meeting.utterances[0].text == "Hej allihopa. Good morning.")
        #expect(meeting.utterances[0].start == 0)
        #expect(meeting.utterances[0].end == 5)
        #expect(meeting.utterances[0].words?.count == 4)
    }

    @Test("Merging with the previous turn keeps the earlier turn's speaker and id")
    func mergeWithPreviousKeepsEarlierIdentity() {
        var meeting = makeMeeting()
        let firstID = meeting.utterances[0].id
        let secondID = meeting.utterances[1].id

        let survivor = meeting.mergeUtterance(secondID, with: .previous)

        #expect(survivor == firstID)
        #expect(meeting.utterances.count == 1)
        #expect(meeting.utterances[0].speakerId == "A")
    }

    @Test("The absorbed speaker stays on the roster even with no lines left")
    func mergeKeepsTheAbsorbedSpeakerOnTheRoster() {
        var meeting = makeMeeting()
        meeting.mergeUtterance(meeting.utterances[0].id, with: .next)

        #expect(meeting.speakers.count == 2)
        #expect(meeting.speaker("B") != nil)
        #expect(!meeting.utterances.contains { $0.speakerId == "B" })
    }

    @Test("Merging at the ends of the transcript is refused")
    func mergeAtTranscriptEndsIsRefused() {
        var meeting = makeMeeting()

        #expect(meeting.mergeUtterance(meeting.utterances[0].id, with: .previous) == nil)
        #expect(meeting.mergeUtterance(meeting.utterances[1].id, with: .next) == nil)
        #expect(meeting.utterances.count == 2)
    }

    @Test("Merging an edited turn drops word timings for the whole result")
    func mergeWithAnEditedTurnDropsTimings() {
        var meeting = makeMeeting()
        meeting.editText(of: meeting.utterances[1].id, to: "Good morning, everyone.")

        meeting.mergeUtterance(meeting.utterances[0].id, with: .next)

        #expect(meeting.utterances.count == 1)
        #expect(meeting.utterances[0].words == nil)
        #expect(meeting.utterances[0].isEdited)
        #expect(meeting.utterances[0].text == "Hej allihopa. Good morning, everyone.")
    }

    @Test("Split then merge round-trips back to the original turn")
    func splitThenMergeRoundTrips() {
        var meeting = makeMeeting()
        let original = meeting.utterances[0]

        let newID = meeting.splitUtterance(original.id, atWordIndex: 1)
        meeting.mergeUtterance(try! #require(newID), with: .previous)

        #expect(meeting.utterances.count == 2)
        #expect(meeting.utterances[0].id == original.id)
        #expect(meeting.utterances[0].text == original.text)
        #expect(meeting.utterances[0].start == original.start)
        #expect(meeting.utterances[0].end == original.end)
        #expect(meeting.utterances[0].words?.count == original.words?.count)
    }

    // MARK: - Text editing

    @Test("Editing text drops that line's word timings and marks it edited")
    func editingDropsWordTimings() {
        var meeting = makeMeeting()
        meeting.editText(of: meeting.utterances[0].id, to: "Hej på er allihopa.")

        #expect(meeting.utterances[0].text == "Hej på er allihopa.")
        #expect(meeting.utterances[0].words == nil)
        #expect(meeting.utterances[0].isEdited)
    }

    @Test("Editing leaves the turn's own start and end alone")
    func editingKeepsTurnBounds() {
        var meeting = makeMeeting()
        let before = meeting.utterances[0]
        meeting.editText(of: before.id, to: "Något helt annat.")

        #expect(meeting.utterances[0].start == before.start)
        #expect(meeting.utterances[0].end == before.end)
    }

    @Test("Editing one line leaves every other line's timings intact")
    func editingIsLocalToOneLine() {
        var meeting = makeMeeting()
        meeting.editText(of: meeting.utterances[0].id, to: "Ändrat.")

        #expect(meeting.utterances[1].words?.count == 2)
        #expect(meeting.utterances[1].isEdited == false)
    }

    @Test("Saving the same text back doesn't mark the line as edited")
    func unchangedTextIsNotAnEdit() {
        var meeting = makeMeeting()
        meeting.editText(of: meeting.utterances[0].id, to: "Hej allihopa.")

        #expect(meeting.utterances[0].isEdited == false)
        #expect(meeting.utterances[0].words?.count == 2)
    }
}
