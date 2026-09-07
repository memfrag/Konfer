//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// A translation is derived from the transcript, so the rule that matters is
/// when a line is dropped: exactly where the words changed, and nowhere else.
/// Keep a stale line and the pane shows a sentence nobody said; drop one too
/// eagerly and a rename costs two minutes of re-translation.
@MainActor
struct MeetingTranslationTests {

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
            text: "Vi börjar med Anna.",
            words: [
                WordSpan(word: "Vi", start: 3.0, end: 3.2),
                WordSpan(word: "börjar", start: 3.3, end: 3.8),
                WordSpan(word: "med", start: 3.9, end: 4.1),
                WordSpan(word: "Anna.", start: 4.2, end: 5.0)
            ]
        )

        var meeting = Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 6,
            importedAt: Date(),
            language: .swedish,
            speakers: [
                SpeakerLabel(id: "A", name: "Speaker 1", embedding: [1, 0], totalDuration: 2),
                SpeakerLabel(id: "B", name: "Speaker 2", embedding: [0, 1], totalDuration: 2)
            ],
            utterances: [first, second]
        )
        meeting.translation = TranscriptTranslation(
            target: .english,
            lines: [
                TranslatedLine(utteranceID: first.id, text: "Hello everyone."),
                TranslatedLine(utteranceID: second.id, text: "We'll start with Anna.")
            ]
        )
        return meeting
    }

    private func translatedIDs(_ meeting: Meeting) -> Set<UUID> {
        Set(meeting.translation?.lines.map(\.utteranceID) ?? [])
    }

    // MARK: - Edits that drop a line

    @Test("Editing a turn's text drops its translation and leaves the other alone")
    func editingDropsTranslation() {
        var meeting = makeMeeting()
        let edited = meeting.utterances[0].id
        let untouched = meeting.utterances[1].id

        meeting.editText(of: edited, to: "Hej allihopa!")

        #expect(translatedIDs(meeting) == [untouched])
    }

    @Test("An edit that changes nothing keeps the translation")
    func noOpEditKeepsTranslation() {
        var meeting = makeMeeting()
        let id = meeting.utterances[0].id

        meeting.editText(of: id, to: "  Hej allihopa.  ")

        #expect(meeting.translation?.text(for: id) == "Hello everyone.")
    }

    @Test("Splitting a turn leaves neither half translated")
    func splittingDropsTranslation() throws {
        var meeting = makeMeeting()
        let original = meeting.utterances[1].id

        // Split first, then require: `#require` rebinds what it wraps as
        // immutable, and this call mutates the meeting.
        let created = meeting.splitUtterance(original, atWordIndex: 2)
        let second = try #require(created)

        #expect(meeting.translation?.text(for: original) == nil)
        #expect(meeting.translation?.text(for: second) == nil)
        #expect(translatedIDs(meeting) == [meeting.utterances[0].id])
    }

    @Test("Merging two turns drops the translations of both")
    func mergingDropsTranslation() {
        var meeting = makeMeeting()

        let survivor = meeting.mergeUtterance(meeting.utterances[1].id, with: .previous)

        #expect(survivor == meeting.utterances[0].id)
        #expect(meeting.translation?.lines.isEmpty == true)
    }

    @Test("Deleting a turn takes its translation with it")
    func deletingDropsTranslation() {
        var meeting = makeMeeting()
        let removed = meeting.utterances[0].id
        let kept = meeting.utterances[1].id

        meeting.removeUtterance(removed)

        #expect(translatedIDs(meeting) == [kept])
    }

    @Test("A replacement inside a single word drops the translation even though the timings survive")
    func replacingInsideAWordDropsTranslation() throws {
        var meeting = makeMeeting()
        let id = meeting.utterances[1].id
        let match = try #require(
            TranscriptSearch.matches(for: "Anna", in: meeting.utterances).first
        )

        let kind = meeting.replace(match, with: "Hanna")

        #expect(kind == .keepsTimings)
        #expect(meeting.utterances[1].words != nil)
        #expect(meeting.translation?.text(for: id) == nil)
    }

    @Test("Replacing across several words drops the translation with the timings")
    func replacingAcrossWordsDropsTranslation() throws {
        var meeting = makeMeeting()
        let id = meeting.utterances[1].id
        let match = try #require(
            TranscriptSearch.matches(for: "med Anna", in: meeting.utterances).first
        )

        let kind = meeting.replace(match, with: "med Hanna")

        #expect(kind == .dropsTimings)
        #expect(meeting.translation?.text(for: id) == nil)
    }

    // MARK: - Edits that keep it

    @Test("Renaming a speaker leaves every translation in place")
    func renamingSpeakerKeepsTranslations() {
        var meeting = makeMeeting()
        let before = translatedIDs(meeting)

        meeting.renameSpeaker("A", to: "Anna")

        #expect(translatedIDs(meeting) == before)
    }

    @Test("Merging two speakers leaves every translation in place")
    func mergingSpeakersKeepsTranslations() {
        var meeting = makeMeeting()
        let before = translatedIDs(meeting)

        meeting.mergeSpeaker("B", into: "A")

        #expect(translatedIDs(meeting) == before)
    }

    @Test("Reassigning a turn leaves its translation in place")
    func reassigningKeepsTranslation() {
        var meeting = makeMeeting()
        let id = meeting.utterances[0].id

        meeting.reassign(id, to: "B")

        #expect(meeting.translation?.text(for: id) == "Hello everyone.")
    }

    @Test("Trimming hides turns without forgetting their translations")
    func trimmingKeepsTranslations() {
        var meeting = makeMeeting()
        let before = translatedIDs(meeting)

        meeting.keep(KeptRange(start: 2.5, end: 6))

        #expect(meeting.keptUtterances.count == 1)
        #expect(translatedIDs(meeting) == before)
    }

    @Test("Removing the translation clears it entirely")
    func removingTranslation() {
        var meeting = makeMeeting()

        meeting.removeTranslation()

        #expect(meeting.translation == nil)
    }

    @Test("Dropping lines on an untranslated meeting does nothing")
    func droppingWithoutATranslation() {
        var meeting = makeMeeting()
        meeting.removeTranslation()

        meeting.dropTranslations(for: [meeting.utterances[0].id])

        #expect(meeting.translation == nil)
    }

    // MARK: - Lookup

    @Test("Lines can be looked up by the turn they belong to")
    func lookup() throws {
        let meeting = makeMeeting()
        let translation = try #require(meeting.translation)
        let first = meeting.utterances[0].id

        #expect(translation.byUtterance[first] == "Hello everyone.")
        #expect(translation.byUtterance.count == 2)
        #expect(translation.text(for: UUID()) == nil)
    }

    // MARK: - Persistence

    @Test("A translated meeting survives a round trip through JSON")
    func roundTrips() throws {
        let meeting = makeMeeting()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(Meeting.self, from: encoder.encode(meeting))

        #expect(decoded.translation?.target == .english)
        #expect(decoded.translation?.lines.count == 2)
        #expect(decoded.translation?.text(for: meeting.utterances[0].id) == "Hello everyone.")
    }

    @Test("A meeting saved before translation existed still decodes")
    func decodesWithoutTranslation() throws {
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(UUID().uuidString)",
          "title": "Old meeting",
          "audioPath": "/tmp/old.m4a",
          "duration": 60,
          "importedAt": "2026-01-02T03:04:05Z",
          "language": "swedish",
          "speakers": [],
          "utterances": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meeting = try decoder.decode(Meeting.self, from: Data(json.utf8))

        #expect(meeting.translation == nil)
        #expect(meeting.title == "Old meeting")
    }
}
