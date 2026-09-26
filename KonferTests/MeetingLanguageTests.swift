//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import Speech
@testable import Konfer

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

    @Test("The picker offers ten languages, in the order it should show them")
    func casesAreExplicitLanguagesInPickerOrder() {
        // Order is deliberate and user-visible: the two Konfer was built for,
        // then the three it grew for, then the ones Apple already covered.
        #expect(MeetingLanguage.allCases == [
            .english, .swedish, .danish, .dutch, .polish,
            .german, .spanish, .french, .italian, .portuguese,
        ])
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

    @Test("Swedish is transcribed by KB-Whisper Large, the model trained for it")
    func swedishUsesKBWhisperLarge() {
        #expect(ASRBackendKind(transcribing: .swedish) == .kbWhisperLarge)
    }

    @Test(
        "The languages Apple covers go to Apple",
        arguments: [MeetingLanguage.english, .german, .spanish, .french, .italian, .portuguese]
    )
    func appleLanguagesUseAppleSpeech(_ language: MeetingLanguage) {
        #expect(ASRBackendKind(transcribing: language) == .appleSpeech)
    }

    @Test(
        "Danish, Dutch and Polish, which nothing else covers, go to stock Whisper",
        arguments: [MeetingLanguage.danish, .dutch, .polish]
    )
    func unservedLanguagesUseWhisperLargeV3(_ language: MeetingLanguage) {
        #expect(ASRBackendKind(transcribing: language) == .whisperLargeV3)
    }

    @Test(
        "Apple's languages start on Apple, and offer stock Whisper as the alternative",
        arguments: [MeetingLanguage.english, .german, .spanish, .french, .italian, .portuguese]
    )
    func appleLanguagesOfferWhisper(_ language: MeetingLanguage) {
        #expect(ASRBackendKind.choices(for: language) == [.appleSpeech, .whisperLargeV3])
    }

    @Test(
        "Swedish, Danish, Dutch and Polish have exactly one model, so no choice to show",
        arguments: [MeetingLanguage.swedish, .danish, .dutch, .polish]
    )
    func someLanguagesHaveNoChoice(_ language: MeetingLanguage) {
        #expect(ASRBackendKind.choices(for: language) == [ASRBackendKind(transcribing: language)])
    }

    @Test("Every model a language offers can actually transcribe it, the default first")
    func everyChoiceIsWorkable() {
        for language in MeetingLanguage.allCases {
            let choices = ASRBackendKind.choices(for: language)
            #expect(choices.first == ASRBackendKind(transcribing: language))
            #expect(choices.allSatisfy { $0.supports(language) })
        }
    }

    @Test("Røst, removed, is offered for nothing and can transcribe nothing")
    func roestIsRetired() {
        for language in MeetingLanguage.allCases {
            #expect(!ASRBackendKind.choices(for: language).contains(.roestWhisper))
            #expect(!ASRBackendKind.roestWhisper.supports(language))
        }
    }

    @Test("A Danish meeting from before models were recorded counts as stock Whisper, which made it")
    func olderDanishMeetingsWereLargeV3() throws {
        let older = try decoded(try encoded(meeting(language: .danish)))

        #expect(older.transcriptionModel == nil)
        #expect(older.model == .whisperLargeV3)
    }

    @Test("A meeting's recorded model survives a round trip")
    func recordedModelRoundTrips() throws {
        var english = meeting(language: .english)
        english.transcriptionModel = .whisperLargeV3

        #expect(try decoded(try encoded(english)).model == .whisperLargeV3)
    }

    @Test("A meeting Røst made still loads, and still says Røst made it")
    func roestMeetingsStillDecode() throws {
        // Written by 1.4, before Røst was removed. Failing to decode it would
        // drop the meeting from the library, not merely relabel it.
        var stored = try #require(
            JSONSerialization.jsonObject(with: try encoded(meeting(language: .danish))) as? [String: Any]
        )
        stored["transcriptionModel"] = "roest-whisper"

        #expect(try decoded(JSONSerialization.data(withJSONObject: stored)).model == .roestWhisper)
    }

    @Test("Apple is never handed a language it has no locale for")
    func appleIsNeverGivenAnUnsupportedLanguage() async {
        let supported = await SpeechTranscriber.supportedLocales
            .compactMap { $0.language.languageCode?.identifier }
        for language in MeetingLanguage.allCases
        where ASRBackendKind(transcribing: language) == .appleSpeech {
            #expect(supported.contains(language.code))
        }
    }

    @Test("Every Apple language resolves to a locale of that same language")
    func resolvedLocaleMatchesTheLanguage() async throws {
        for language in MeetingLanguage.allCases
        where ASRBackendKind(transcribing: language) == .appleSpeech {
            let locale = try await AppleSpeechBackend.resolvedLocale(for: language)
            #expect(locale.language.languageCode?.identifier == language.code)
        }
    }

    @Test("A language Apple doesn't have resolves to nothing rather than the wrong one")
    func resolvedLocaleRefusesAnUnsupportedLanguage() async {
        await #expect(throws: PipelineError.self) {
            try await AppleSpeechBackend.resolvedLocale(for: .swedish)
        }
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
