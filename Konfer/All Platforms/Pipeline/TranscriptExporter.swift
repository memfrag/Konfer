//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Renders a meeting for export.
///
/// Four formats, all reflecting every edit and all stopping at the trim.
/// Prose in Markdown and JSON; cues in WebVTT and SubRip, which
/// ``SubtitleExporter`` cuts at the model's own word timings rather than
/// putting a whole speaker turn on screen at once.
///
nonisolated enum TranscriptExporter {

    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case json
        case webVTT
        case subRip

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .markdown: "Markdown"
            case .json: "JSON"
            case .webVTT: "WebVTT Subtitles"
            case .subRip: "SubRip Subtitles"
            }
        }

        var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .json: "json"
            case .webVTT: "vtt"
            case .subRip: "srt"
            }
        }

        /// Whether exporting this format in the translation language produces
        /// a different file.
        ///
        /// JSON does not: it carries both texts already, so a second file
        /// would be the same bytes under a longer name.
        var hasTranslatedVariant: Bool { self != .json }
    }

    static func data(
        for meeting: Meeting,
        format: Format,
        rendering: TranscriptRendering = .original
    ) throws -> Data {
        switch format {
        case .markdown:
            Data(markdown(for: meeting, rendering: rendering).utf8)
        case .json:
            // Always both languages, whatever was asked for.
            try json(for: meeting)
        case .webVTT:
            Data(SubtitleExporter.webVTT(for: meeting, rendering: rendering).utf8)
        case .subRip:
            Data(SubtitleExporter.srt(for: meeting, rendering: rendering).utf8)
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
    ///
    /// - Parameter text: What to put after the attribution, when that is not
    ///   the turn's own text — the pane copies the language it is showing.
    static func plainLine(
        for utterance: Utterance,
        speaker: String,
        text: String? = nil
    ) -> String {
        "\(attribution(for: utterance, speaker: speaker)) \(text ?? utterance.text)"
    }

    // MARK: - Markdown

    static func markdown(
        for meeting: Meeting,
        rendering: TranscriptRendering = .original
    ) -> String {
        var lines: [String] = []

        lines.append("# \(meeting.title)")
        lines.append("")

        let date = meeting.importedAt.formatted(date: .abbreviated, time: .shortened)
        lines.append("*\(Timecode.short(meeting.duration)) · transcribed \(date)*")

        if let kept = meeting.keptRange {
            lines.append("")
            lines.append(
                "*Trimmed to \(Timecode.short(kept.start))–\(Timecode.short(kept.end)); "
                + "the rest of the recording is not included.*"
            )
        }

        if meeting.degraded == .diarization {
            lines.append("")
            lines.append(
                "> Speaker identification did not produce a result for this "
                + "recording, so every line is attributed to a single unknown speaker."
            )
        }

        // Said in the file itself, not only in the filename, because a
        // Markdown transcript is read far from wherever it was saved and a
        // machine translation should never be mistaken for a record of what
        // was said.
        if rendering == .translated, let target = meeting.translationTarget {
            lines.append("")
            lines.append(
                "*Translated from \(meeting.language.displayName) to "
                + "\(target.displayName) on device. The recording is in "
                + "\(meeting.language.displayName).*"
            )

            let untranslated = meeting.keptUtterances.filter {
                meeting.translatedText(for: $0) == nil
            }
            if !untranslated.isEmpty {
                let one = untranslated.count == 1
                lines.append("")
                lines.append(
                    "*\(untranslated.count) \(one ? "line has" : "lines have") no "
                    + "translation and \(one ? "is" : "are") shown in "
                    + "\(meeting.language.displayName).*"
                )
            }
        }
        lines.append("")

        for utterance in meeting.keptUtterances {
            let name = meeting.displayName(for: utterance.speakerId)
            let attribution = Self.attribution(for: utterance, speaker: name)
            lines.append("**\(attribution)** \(meeting.text(for: utterance, rendering: rendering))")
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
