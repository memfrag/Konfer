//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Konfer's JSON export, read back in.
///
/// The promise is a round trip: a meeting exported and imported again is the
/// same meeting, except for what the export leaves out on purpose — the
/// recording, the voices, and the ids. Most of these tests export a real
/// ``Meeting`` through ``TranscriptExporter`` rather than writing JSON by hand,
/// so a field added to one side and not the other fails here.
struct KonferTranscriptTests {

    // MARK: - Fixtures

    /// Whole seconds: the export writes ISO 8601, which has no fractions.
    private let transcribedAt = Date(timeIntervalSince1970: 1_780_000_000)
    private let translatedAt = Date(timeIntervalSince1970: 1_780_000_600)

    private func makeMeeting() -> Meeting {
        let first = Utterance(
            speakerId: "S1", start: 12, end: 15, text: "Hej allihopa.",
            words: [
                WordSpan(word: "Hej", start: 12, end: 12.6),
                WordSpan(word: "allihopa.", start: 12.6, end: 15)
            ]
        )
        let second = Utterance(
            speakerId: "S2", start: 20, end: 24, text: "Vi börjar med budgeten.",
            isEdited: true
        )
        let third = Utterance(
            speakerId: "S1", start: 30, end: 33, text: "Bra.",
            words: [WordSpan(word: "Bra.", start: 30, end: 33)]
        )

        var meeting = Meeting(
            id: UUID(),
            title: "Styrelsemöte",
            audioPath: "/tmp/styrelsemote.m4a",
            duration: 3_600,
            importedAt: transcribedAt,
            language: .swedish,
            speakers: [
                SpeakerLabel(id: "S1", name: "Anna", isNamed: true, embedding: [0.1, 0.2],
                             totalDuration: 6, side: .microphone),
                SpeakerLabel(id: "S2", name: "Speaker 2", embedding: [0.3],
                             totalDuration: 4, side: .systemAudio)
            ],
            utterances: [first, second, third]
        )
        meeting.transcriptionModel = .kbWhisperLarge
        meeting.translation = TranscriptTranslation(
            target: .english,
            lines: [
                TranslatedLine(utteranceID: first.id, text: "Hello everyone."),
                TranslatedLine(utteranceID: third.id, text: "Good.")
            ],
            translatedAt: translatedAt
        )
        return meeting
    }

    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    private func roundTrip(_ meeting: Meeting) throws -> Meeting {
        let url = try write(TranscriptExporter.data(for: meeting, format: .json))
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .konfer(let transcript) = try ImportedTranscript.read(contentsOf: url) else {
            Issue.record("A Konfer export was not read as one")
            throw CancellationError()
        }
        return transcript.meeting()
    }

    private func read(_ json: String) throws -> ImportedTranscript {
        let url = try write(Data(json.utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        return try ImportedTranscript.read(contentsOf: url)
    }

    // MARK: - Round trip

    @Test("An exported meeting comes back with its title, length, date, language and model")
    func meetingLevelFields() throws {
        let original = makeMeeting()
        let imported = try roundTrip(original)

        #expect(imported.title == "Styrelsemöte")
        #expect(imported.duration == 3_600)
        #expect(imported.importedAt == transcribedAt)
        #expect(imported.language == .swedish)
        #expect(imported.transcriptionModel == .kbWhisperLarge)
        #expect(imported.degraded == nil)
        #expect(imported.wasFastTranscribed == nil)
    }

    @Test("Speakers come back with their names, whether they were named, and which side they were on")
    func speakersSurvive() throws {
        let imported = try roundTrip(makeMeeting())

        #expect(imported.speakers.map(\.id) == ["S1", "S2"])
        #expect(imported.speakers.map(\.name) == ["Anna", "Speaker 2"])
        #expect(imported.speakers.map(\.isNamed) == [true, false])
        #expect(imported.speakers.map(\.side) == [.microphone, .systemAudio])
        #expect(imported.speakers.map(\.totalDuration) == [6, 4])
    }

    @Test("Voices are not imported, so an imported speaker can't be matched or enrolled")
    func noEmbeddings() throws {
        let imported = try roundTrip(makeMeeting())

        #expect(imported.speakers.allSatisfy { $0.embedding.isEmpty })
    }

    @Test("Turns come back as they were cut, with their word timings and hand edits")
    func turnsSurvive() throws {
        let original = makeMeeting()
        let imported = try roundTrip(original)

        #expect(imported.utterances.map(\.speakerId) == original.utterances.map(\.speakerId))
        #expect(imported.utterances.map(\.start) == original.utterances.map(\.start))
        #expect(imported.utterances.map(\.end) == original.utterances.map(\.end))
        #expect(imported.utterances.map(\.text) == original.utterances.map(\.text))
        #expect(imported.utterances.map(\.words) == original.utterances.map(\.words))
        #expect(imported.utterances.map(\.isEdited) == [false, true, false])
    }

    @Test("The translation comes back attached to the right turns, gaps and all")
    func translationSurvives() throws {
        let imported = try roundTrip(makeMeeting())
        let translation = try #require(imported.translation)

        #expect(translation.target == .english)
        #expect(translation.translatedAt == translatedAt)
        #expect(imported.utterances.map { translation.text(for: $0.id) }
                == ["Hello everyone.", nil, "Good."])
    }

    @Test("The meeting is new: a fresh id, fresh turn ids, and no recording")
    func newIdentity() throws {
        let original = makeMeeting()
        let imported = try roundTrip(original)

        #expect(imported.id != original.id)
        #expect(Set(imported.utterances.map(\.id)).isDisjoint(with: original.utterances.map(\.id)))
        #expect(imported.audioPath.isEmpty)
        #expect(!imported.audioExists)
    }

    @Test("A trimmed meeting comes back trimmed, with only the lines it kept")
    func trimSurvives() throws {
        var original = makeMeeting()
        original.keptRange = KeptRange(start: 18, end: 40)
        let imported = try roundTrip(original)

        #expect(imported.keptRange == KeptRange(start: 18, end: 40))
        #expect(imported.utterances.map(\.text) == ["Vi börjar med budgeten.", "Bra."])
    }

    @Test("A run that couldn't identify speakers, or ran in fast mode, stays marked")
    func marksSurvive() throws {
        var original = makeMeeting()
        original.degraded = .diarization
        original.wasFastTranscribed = true
        let imported = try roundTrip(original)

        #expect(imported.degraded == .diarization)
        #expect(imported.wasFastTranscribed == true)
    }

    // MARK: - Telling the formats apart

    @Test("A Klang export is still read as Klang")
    func klangStillReads() throws {
        let transcript = try read(
            #"{"texts":[{"text":"Hej.","start":0.5,"end":1.5,"speaker":"Talare 1"}]}"#
        )
        guard case .klang = transcript else {
            Issue.record("Expected a Klang transcript, got \(transcript)")
            return
        }
        #expect(transcript.declaredLanguage == nil)
    }

    @Test("A Konfer export declares its language, so the sheet doesn't ask")
    func konferDeclaresLanguage() throws {
        let url = try write(TranscriptExporter.data(for: makeMeeting(), format: .json))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try ImportedTranscript.read(contentsOf: url).declaredLanguage == .swedish)
    }

    @Test("JSON that is neither format is rejected")
    func rejectsOtherJSON() {
        #expect(throws: TranscriptImportError.self) {
            try read(#"{"segments":[{"text":"Hej"}]}"#)
        }
    }

    // MARK: - Older and odder files

    /// The shape of an export written before import existed: no `named`, no
    /// `side`, no `model`.
    private func olderExport(speakers: String, language: String = "swedish", text: String = "Hej.") -> String {
        """
        {
          "title": "Gammalt möte", "duration": 60, "importedAt": "2026-06-01T09:00:00Z",
          "language": "\(language)",
          "speakers": [\(speakers)],
          "transcript": [
            {"speakerId": "S1", "speaker": "Anna", "start": 1, "end": 2,
             "text": "\(text)", "isEdited": false}
          ]
        }
        """
    }

    @Test("An older export without the named flag treats generated names as placeholders")
    func infersNamedFromOlderExports() throws {
        let transcript = try read(olderExport(speakers: """
            {"id": "S1", "name": "Anna", "totalDuration": 1},
            {"id": "S2", "name": "Speaker 2", "totalDuration": 0},
            {"id": "unknown", "name": "Unknown speaker", "totalDuration": 0}
            """))
        guard case .konfer(let konfer) = transcript else {
            Issue.record("An older export was not read as Konfer's")
            return
        }

        #expect(konfer.meeting().speakers.map(\.isNamed) == [true, false, false])
    }

    @Test("A turn naming a speaker missing from the roster gets one, rather than pointing at nobody")
    func addsMissingSpeakers() throws {
        let transcript = try read(olderExport(speakers: ""))
        guard case .konfer(let konfer) = transcript else {
            Issue.record("An export with an empty roster was not read as Konfer's")
            return
        }

        let meeting = konfer.meeting()
        #expect(meeting.speakers.map(\.id) == ["S1"])
        #expect(meeting.speakers.first?.name == "Anna")
    }

    @Test("An export in a language this version doesn't know is refused, not guessed")
    func refusesUnknownLanguage() {
        #expect(throws: TranscriptImportError.self) {
            try read(olderExport(speakers: "", language: "klingon"))
        }
    }

    @Test("An export with nothing said in it is refused")
    func refusesEmptyExport() {
        #expect(throws: TranscriptImportError.self) {
            try read(olderExport(speakers: "", text: " "))
        }
    }
}
