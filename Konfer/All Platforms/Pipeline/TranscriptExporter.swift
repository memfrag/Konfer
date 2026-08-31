//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Renders a meeting for export.
///
/// Two formats, both reflecting every edit. Subtitle formats were deliberately
/// left out: the goal is readable prose, and a speaker turn makes a fine
/// paragraph but a useless subtitle cue.
///
nonisolated enum TranscriptExporter {

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case json

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .markdown: "Markdown"
            case .json: "JSON"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .json: "json"
            }
        }
    }

    static func data(for meeting: Meeting, format: Format) throws -> Data {
        switch format {
        case .markdown:
            Data(markdown(for: meeting).utf8)
        case .json:
            try json(for: meeting)
        }
    }

    // MARK: - Line formatting

    /// `[00:12:34] Anna:` — the attribution that precedes a turn's text.
    ///
    /// Shared by the Markdown export and the clipboard, so a copied line and an
    /// exported one can't drift into different shapes.
    static func attribution(for utterance: Utterance, speaker: String) -> String {
        "[\(Timecode.padded(utterance.start))] \(speaker):"
    }

    /// A whole turn as plain text, for the clipboard.
    static func plainLine(for utterance: Utterance, speaker: String) -> String {
        "\(attribution(for: utterance, speaker: speaker)) \(utterance.text)"
    }

    // MARK: - Markdown

    static func markdown(for meeting: Meeting) -> String {
        var lines: [String] = []

        lines.append("# \(meeting.title)")
        lines.append("")

        let date = meeting.importedAt.formatted(date: .abbreviated, time: .shortened)
        lines.append("*\(Timecode.short(meeting.duration)) · transcribed \(date)*")

        if meeting.degraded == .diarization {
            lines.append("")
            lines.append(
                "> Speaker identification did not produce a result for this "
                + "recording, so every line is attributed to a single unknown speaker."
            )
        }
        lines.append("")

        for utterance in meeting.utterances {
            let name = meeting.displayName(for: utterance.speakerId)
            let attribution = Self.attribution(for: utterance, speaker: name)
            lines.append("**\(attribution)** \(utterance.text)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    private static func json(for meeting: Meeting) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(ExportedMeeting(meeting))
    }
}

// MARK: - Export shape

/// The JSON export.
///
/// Deliberately its own type rather than encoding ``Meeting`` directly: the
/// export is a published format, so it shouldn't drift every time the internal
/// model changes. Voice embeddings are left out — they are large, meaningless
/// outside Konfer, and are biometric data that has no business in a file
/// someone might share.
private nonisolated struct ExportedMeeting: Encodable {

    struct Speaker: Encodable {
        let id: String
        let name: String
        let totalDuration: TimeInterval
    }

    struct Turn: Encodable {
        struct Word: Encodable {
            let word: String
            let start: TimeInterval
            let end: TimeInterval
        }

        let speakerId: String
        let speaker: String
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let isEdited: Bool
        let words: [Word]?
    }

    let title: String
    let duration: TimeInterval
    let importedAt: Date
    let language: String
    let degraded: String?
    let speakers: [Speaker]
    let transcript: [Turn]

    init(_ meeting: Meeting) {
        title = meeting.title
        duration = meeting.duration
        importedAt = meeting.importedAt
        language = meeting.language.rawValue
        degraded = meeting.degraded?.rawValue
        speakers = meeting.speakers.map {
            Speaker(id: $0.id, name: $0.name, totalDuration: $0.totalDuration)
        }
        transcript = meeting.utterances.map { utterance in
            Turn(
                speakerId: utterance.speakerId,
                speaker: meeting.displayName(for: utterance.speakerId),
                start: utterance.start,
                end: utterance.end,
                text: utterance.text,
                isEdited: utterance.isEdited,
                words: utterance.words?.map {
                    Turn.Word(word: $0.word, start: $0.start, end: $0.end)
                }
            )
        }
    }
}
