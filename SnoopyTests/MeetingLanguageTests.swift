//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// The language is the one thing the user declares, and everything else follows
/// from it — including which model runs.
///
/// Meetings transcribed before the automatic option went away still say
/// `"auto"` on disk, and `MeetingStore` drops anything it fails to decode, so
/// the old value has to keep reading as the language it actually ran as.
struct MeetingLanguageTests {

    // MARK: - Fixtures

    private func meeting(language: MeetingLanguage) -> Meeting {
        Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 60,
            importedAt: Date(timeIntervalSince1970: 0),
            language: language,
            speakers: [SpeakerLabel(id: "Speaker 1", name: "Anna")],
            utterances: []
        )
    }

    private func encoded(_ meeting: Meeting) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(meeting)
    }

    private func decoded(_ data: Data) throws -> Meeting {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Meeting.self, from: data)
    }

    /// Rewrites the stored language to a value this version no longer defines.
    private func withStoredLanguage(_ raw: String, in data: Data) throws -> Data {
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\"language\":\"english\"", with: "\"language\":\"\(raw)\"")
        return Data(json.utf8)
    }

    // MARK: - Tests

    @Test("The picker offers Swedish and English, and nothing else")
    func casesAreExplicitLanguagesOnly() {
        #expect(MeetingLanguage.allCases == [.swedish, .english])
    }

    @Test("A meeting stored as auto reads back as Swedish, the language it ran as")
    func legacyAutoDecodesAsSwedish() throws {
        let data = try withStoredLanguage("auto", in: try encoded(meeting(language: .english)))
        #expect(try decoded(data).language == .swedish)
    }

    @Test("A meeting stored as auto still loads rather than being dropped")
    func legacyAutoStillDecodes() throws {
        let original = meeting(language: .english)
        let data = try withStoredLanguage("auto", in: try encoded(original))
        #expect(try decoded(data).title == original.title)
    }

    @Test("An unrecognised language falls back rather than failing the meeting")
    func unknownLanguageDecodes() throws {
        let data = try withStoredLanguage("klingon", in: try encoded(meeting(language: .english)))
        #expect(try decoded(data).language == .swedish)
    }

    @Test("English is transcribed by Apple's own recognition")
    func englishUsesAppleSpeech() {
        #expect(ASRBackendKind(transcribing: .english) == .appleSpeech)
    }

    @Test("Swedish is transcribed by KB-Whisper Large")
    func swedishUsesKBWhisperLarge() {
        #expect(ASRBackendKind(transcribing: .swedish) == .kbWhisperLarge)
    }

    @Test("Every language gets a model that can actually transcribe it")
    func everyLanguageHasAWorkableModel() {
        for language in MeetingLanguage.allCases {
            #expect(ASRBackendKind(transcribing: language).supports(language))
        }
    }

    @Test("A declared language survives a round trip untouched")
    func roundTripKeepsLanguage() throws {
        for language in MeetingLanguage.allCases {
            #expect(try decoded(try encoded(meeting(language: language))).language == language)
        }
    }
}
