//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// An export in the translation language is still an export of a recording
/// nobody made in that language, so what matters is that it says so — and that
/// JSON, being a data format, never has to choose.
@MainActor
struct TranslatedExportTests {

    // MARK: - Fixture

    private func makeMeeting(translated: Bool = true, partly: Bool = false) -> Meeting {
        let first = Utterance(
            speakerId: "A",
            start: 12,
            end: 14,
            text: "Hej allihopa.",
            words: [
                WordSpan(word: "Hej", start: 12, end: 12.5),
                WordSpan(word: "allihopa.", start: 12.6, end: 14.0)
            ]
        )
        let second = Utterance(
            speakerId: "B",
            start: 20,
            end: 22,
            text: "Vi börjar med budgeten."
        )

        var meeting = Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 600,
            importedAt: Date(timeIntervalSince1970: 1_767_225_600),
            language: .swedish,
            speakers: [
                SpeakerLabel(id: "A", name: "Anna", totalDuration: 2),
                SpeakerLabel(id: "B", name: "Björn", totalDuration: 2)
            ],
            utterances: [first, second]
        )

        guard translated else { return meeting }

        var lines = [TranslatedLine(utteranceID: first.id, text: "Hello everyone.")]
        if !partly {
            lines.append(TranslatedLine(utteranceID: second.id, text: "Let's start with the budget."))
        }
        meeting.translation = TranscriptTranslation(target: .english, lines: lines)
        return meeting
    }

    private func exportedJSON(_ meeting: Meeting) throws -> [String: Any] {
        let data = try TranscriptExporter.data(for: meeting, format: .json)
        return try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    // MARK: - Markdown

    @Test("Markdown in the translated rendering prints the translated text")
    func markdownUsesTheTranslation() {
        let markdown = TranscriptExporter.markdown(for: makeMeeting(), rendering: .translated)

        #expect(markdown.contains("**[00:00:12] Anna:** Hello everyone."))
        #expect(markdown.contains("**[00:00:20] Björn:** Let's start with the budget."))
        #expect(!markdown.contains("Hej allihopa."))
    }

    @Test("Markdown says the transcript was translated, and from what")
    func markdownSaysItWasTranslated() {
        let markdown = TranscriptExporter.markdown(for: makeMeeting(), rendering: .translated)

        #expect(markdown.contains("Translated from Swedish to English on device."))
        #expect(markdown.contains("The recording is in Swedish."))
    }

    @Test("Markdown counts the lines it had to leave in the original")
    func markdownCountsUntranslatedLines() {
        let markdown = TranscriptExporter.markdown(
            for: makeMeeting(partly: true), rendering: .translated
        )

        #expect(markdown.contains("1 line has no translation and is shown in Swedish."))
        #expect(markdown.contains("**[00:00:20] Björn:** Vi börjar med budgeten."))
    }

    @Test("Markdown in the original rendering is untouched by a translation being present")
    func markdownOriginalIsUnchanged() {
        #expect(
            TranscriptExporter.markdown(for: makeMeeting())
                == TranscriptExporter.markdown(for: makeMeeting(translated: false))
        )
    }

    @Test("Speaker names are not translated")
    func namesAreNotTranslated() {
        let markdown = TranscriptExporter.markdown(for: makeMeeting(), rendering: .translated)

        #expect(markdown.contains("Björn:"))
    }

    // MARK: - JSON

    @Test("JSON carries both the original and the translated text for every turn")
    func jsonCarriesBoth() throws {
        let object = try exportedJSON(makeMeeting())
        let transcript = try #require(object["transcript"] as? [[String: Any]])

        #expect(transcript[0]["text"] as? String == "Hej allihopa.")
        #expect(transcript[0]["translatedText"] as? String == "Hello everyone.")
        #expect(transcript[1]["translatedText"] as? String == "Let's start with the budget.")
    }

    @Test("JSON names the languages it was translated between")
    func jsonNamesTheLanguages() throws {
        let object = try exportedJSON(makeMeeting())
        let translation = try #require(object["translation"] as? [String: Any])

        #expect(translation["from"] as? String == "swedish")
        #expect(translation["to"] as? String == "english")
        #expect(translation["translatedAt"] is String)
    }

    @Test("A turn with no translation has no translated text in the JSON")
    func jsonOmitsMissingTurns() throws {
        let object = try exportedJSON(makeMeeting(partly: true))
        let transcript = try #require(object["transcript"] as? [[String: Any]])

        #expect(transcript[0]["translatedText"] as? String == "Hello everyone.")
        #expect(transcript[1]["translatedText"] == nil)
    }

    @Test("JSON for an untranslated meeting has no translation key at all")
    func jsonOmitsTheBlockEntirely() throws {
        let object = try exportedJSON(makeMeeting(translated: false))

        #expect(object["translation"] == nil)
        #expect(object["title"] as? String == "Standup")
    }

    @Test("Asking for JSON in the translated rendering is the same file")
    func jsonHasNoVariant() throws {
        let original = try TranscriptExporter.data(for: makeMeeting(), format: .json)
        let translated = try TranscriptExporter.data(
            for: makeMeeting(), format: .json, rendering: .translated
        )

        #expect(original == translated)
        #expect(!TranscriptExporter.Format.json.hasTranslatedVariant)
        #expect(TranscriptExporter.Format.markdown.hasTranslatedVariant)
        #expect(TranscriptExporter.Format.subRip.hasTranslatedVariant)
        #expect(TranscriptExporter.Format.webVTT.hasTranslatedVariant)
    }

    // MARK: - Clipboard

    @Test("A copied line can carry the language the pane is showing")
    func plainLineTakesAnOverride() {
        let meeting = makeMeeting()
        let utterance = meeting.utterances[0]

        #expect(
            TranscriptExporter.plainLine(for: utterance, speaker: "Anna")
                == "[00:00:12] Anna: Hej allihopa."
        )
        #expect(
            TranscriptExporter.plainLine(for: utterance, speaker: "Anna", text: "Hello everyone.")
                == "[00:00:12] Anna: Hello everyone."
        )
    }
}
