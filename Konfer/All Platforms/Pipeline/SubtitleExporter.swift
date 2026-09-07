//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - SubtitleCue

/// One subtitle, as both formats need it.
///
/// Cues are shared rather than each format building its own, so WebVTT and
/// SubRip can only ever differ in how they are written down — not in where
/// they break or what they say.
nonisolated struct SubtitleCue: Equatable, Sendable {

    let start: TimeInterval
    let end: TimeInterval

    /// Set on the first cue of a turn and nil after, so a long turn is
    /// attributed once rather than repeating the name every few seconds.
    let speaker: String?

    /// One line, unwrapped. Wrapping happens where the cue is written down,
    /// because only there is it known what else shares the line: SubRip puts
    /// the speaker's name in front of the words, WebVTT puts it in a tag that
    /// takes no room on screen.
    let text: String
}

// MARK: - SubtitleExporter

/// Renders a transcript as subtitles.
///
/// These were deliberately left out at first, on the grounds that a speaker
/// turn makes a fine paragraph and a useless subtitle cue — half a minute of
/// text on screen at once. That objection is about turns, not about subtitles:
/// ``Utterance/words`` carries the model's own per-word timings, so a turn can
/// be cut into cues at real word boundaries with real times. Only a
/// hand-edited turn, whose timings were dropped when its text changed, still
/// has to go out whole.
///
nonisolated enum SubtitleExporter {

    /// Roughly the width a subtitle line is read comfortably at, and two of
    /// them is the usual ceiling before a cue covers the picture.
    static let maximumLineLength = 42
    static let maximumLines = 2
    static var maximumCharacters: Int { maximumLineLength * maximumLines }

    /// Longer than this on screen and the reader has finished well before the
    /// speaker has.
    static let maximumDuration: TimeInterval = 6

    // MARK: - Cues

    /// The whole transcript as cues, in order.
    ///
    /// Trimmed turns are left out for the same reason they are left out of
    /// Markdown and JSON: an export contains what the meeting contains.
    ///
    /// - Parameter attributionTakesRoom: Whether the speaker's name will sit
    ///   on the first line alongside the words, as it does in SubRip. The
    ///   first cue of each turn is then given that much less to say, so the
    ///   name cannot push the line past the width a subtitle is read at. In
    ///   WebVTT the name is a tag rather than text and this is false.
    static func cues(
        for meeting: Meeting,
        attributionTakesRoom: Bool = false,
        rendering: TranscriptRendering = .original
    ) -> [SubtitleCue] {
        meeting.keptUtterances.flatMap { utterance in
            let speaker = meeting.displayName(for: utterance.speakerId)
            let reserved = attributionTakesRoom ? attribution(for: speaker).count : 0

            let source = split(utterance, firstCueBudget: maximumCharacters - reserved)
                .enumerated()
                .map { index, piece in
                    SubtitleCue(
                        start: piece.start,
                        // A cue nobody can see is worse than one that lingers,
                        // and a word span can be vanishingly short.
                        end: max(piece.end, piece.start + 0.05),
                        speaker: index == 0 ? speaker : nil,
                        text: piece.text
                    )
                }

            guard rendering == .translated,
                  let translated = meeting.translatedText(for: utterance)
            else {
                // A turn with no translation goes out in the original
                // language. Mixed subtitles beat blank ones, and the reader
                // can see for themselves which lines were left behind.
                return source
            }
            return redistribute(translated, across: source)
        }
    }

    /// Spreads one turn's translated text across the cues its original was cut
    /// into.
    ///
    /// Translated text has no word timings — the model timed the words that
    /// were said, and these are not those. ``split(_:firstCueBudget:)`` refuses
    /// to cut an un-timed turn on the grounds that it would have to invent the
    /// times to cut at, and that stands: this invents none. Every start and end
    /// here is a time the recogniser produced for the source. The only thing
    /// chosen is where in the translated sentence to break, which is a claim
    /// about the text and not about the recording.
    ///
    /// Each cue is given words until it has had its share of the translation,
    /// its share being the share of the turn's source characters it carried.
    /// Rejoined, the pieces are exactly the translation: nothing is dropped to
    /// make it fit, because a subtitle that silently loses a clause is worse
    /// than one that runs long, and ``wrapped(_:)`` already folds the surplus.
    ///
    /// A cue that would be left with no words at all — the translation is
    /// shorter than the original, which English against German is routinely —
    /// is folded into the next one that has some. The result spans both, which
    /// is still two real times and one fewer subtitle, rather than a blank
    /// flashing by.
    static func redistribute(_ translated: String, across cues: [SubtitleCue]) -> [SubtitleCue] {
        let words = translated.split(separator: " ", omittingEmptySubsequences: true)
        guard cues.count > 1, !words.isEmpty else {
            guard let only = cues.first else { return [] }
            return [SubtitleCue(
                start: only.start,
                end: cues[cues.count - 1].end,
                speaker: only.speaker,
                text: words.isEmpty ? only.text : words.joined(separator: " ")
            )]
        }

        // How far into the translation each cue's share reaches, measured in
        // characters so a cue carrying a long sentence gets proportionally
        // more of the translation than one carrying three words.
        let sourceTotal = Double(cues.reduce(0) { $0 + $1.text.count })
        let translatedTotal = Double(words.reduce(0) { $0 + $1.count + 1 })
        var reach: [Double] = []
        var running = 0.0
        for cue in cues {
            running += Double(cue.text.count)
            reach.append(sourceTotal > 0 ? running / sourceTotal * translatedTotal : translatedTotal)
        }

        var pieces: [[Substring]] = Array(repeating: [], count: cues.count)
        var index = 0
        var consumed = 0.0
        for word in words {
            while index < cues.count - 1, consumed >= reach[index] { index += 1 }
            pieces[index].append(word)
            consumed += Double(word.count) + 1
        }

        var out: [SubtitleCue] = []
        var groupStart = 0
        for index in cues.indices where !pieces[index].isEmpty {
            out.append(SubtitleCue(
                start: cues[groupStart].start,
                end: cues[index].end,
                // Only the first cue of a turn carries the name, and only the
                // first group can begin at the turn's first cue.
                speaker: cues[groupStart].speaker,
                text: pieces[index].joined(separator: " ")
            ))
            groupStart = index + 1
        }

        // Words ran out before the cues did. The last cue keeps the turn's own
        // end rather than stopping early and leaving a silent gap.
        if groupStart < cues.count, let last = out.popLast() {
            out.append(SubtitleCue(
                start: last.start,
                end: cues[cues.count - 1].end,
                speaker: last.speaker,
                text: last.text
            ))
        }

        return out
    }

    /// How a speaker is written in front of their words.
    static func attribution(for speaker: String) -> String { "\(speaker): " }

    /// A cue as it appears on screen: the name in front of the words when this
    /// is the first cue of a turn, wrapped to the line width.
    ///
    /// Shared by SubRip and by the tx3g track embedded in a video, which both
    /// put the name on the line as plain text rather than in markup. WebVTT
    /// does not use it — there the name is a `<v>` tag taking no room.
    static func displayText(for cue: SubtitleCue) -> String {
        guard let speaker = cue.speaker else { return wrapped(cue.text) }
        return wrapped(attribution(for: speaker) + cue.text)
    }

    private struct Piece {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// Cuts one turn into cues at word boundaries.
    ///
    /// A turn whose timings were dropped by hand-editing goes out as a single
    /// cue however long it is. Splitting it would mean inventing the times to
    /// split at, and a subtitle that claims to know when a word was said is
    /// worse than one that stays on screen too long.
    private static func split(_ utterance: Utterance, firstCueBudget: Int) -> [Piece] {
        guard let words = utterance.words, !words.isEmpty else {
            return [Piece(start: utterance.start, end: utterance.end, text: utterance.text)]
        }

        var pieces: [Piece] = []
        var current: [WordSpan] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            pieces.append(Piece(
                start: first.start,
                end: last.end,
                text: SpeakerAligner.joined(current)
            ))
            current = []
        }

        for word in words {
            if let first = current.first {
                // Only the first cue of a turn carries the speaker's name, so
                // only it is short of room.
                let budget = pieces.isEmpty ? firstCueBudget : maximumCharacters
                let text = SpeakerAligner.joined(current + [word])
                if text.count > budget || word.end - first.start > maximumDuration {
                    flush()
                }
            }
            current.append(word)
        }
        flush()

        return pieces
    }

    /// Breaks a cue's text across at most two lines at word boundaries.
    ///
    /// Greedy rather than balanced: a reader's eye returns to the left margin
    /// either way, and the alternative measures the same string twice to save
    /// a word from the second line.
    static func wrapped(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        var lines: [String] = []
        var line = ""

        for word in words {
            if line.isEmpty {
                line = String(word)
            } else if line.count + 1 + word.count <= maximumLineLength {
                line += " " + word
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }

        // More than the ceiling only happens when a cue is a single very long
        // word or an un-timed turn going out whole; joining the surplus keeps
        // the text intact rather than dropping any of it.
        if lines.count > maximumLines {
            let head = lines.prefix(maximumLines - 1)
            let tail = lines.dropFirst(maximumLines - 1).joined(separator: " ")
            lines = Array(head) + [tail]
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - WebVTT

    static func webVTT(
        for meeting: Meeting,
        rendering: TranscriptRendering = .original
    ) -> String {
        var out = "WEBVTT\n"

        for (index, cue) in cues(for: meeting, rendering: rendering).enumerated() {
            out += "\n\(index + 1)\n"
            out += "\(Timecode.subtitle(cue.start, decimalSeparator: "."))"
            out += " --> "
            out += "\(Timecode.subtitle(cue.end, decimalSeparator: "."))\n"

            // Wrapped before escaping, not after: `&amp;` is five characters
            // standing in for one, and measuring the escaped form would make
            // every line carrying an ampersand needlessly short.
            let body = wrapped(cue.text)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { escapedForVTT(String($0)) }
                .joined(separator: "\n")

            // WebVTT is parsed as markup, so a stray angle bracket in the
            // speech would swallow the rest of the cue.
            if let speaker = cue.speaker {
                out += "<v \(escapedForVTT(speaker))>\(body)\n"
            } else {
                out += "\(body)\n"
            }
        }

        return out
    }

    private static func escapedForVTT(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - SubRip

    static func srt(
        for meeting: Meeting,
        rendering: TranscriptRendering = .original
    ) -> String {
        var out = ""

        let all = cues(for: meeting, attributionTakesRoom: true, rendering: rendering)
        for (index, cue) in all.enumerated() {
            if index > 0 { out += "\n" }
            out += "\(index + 1)\n"
            out += "\(Timecode.subtitle(cue.start, decimalSeparator: ","))"
            out += " --> "
            out += "\(Timecode.subtitle(cue.end, decimalSeparator: ","))\n"

            // SubRip has no markup and no voice tag, so the name goes in front
            // of the words the way a script writes it — and is wrapped with
            // them, since on screen it is simply more text on the line.
            out += "\(displayText(for: cue))\n"
        }

        return out
    }
}
