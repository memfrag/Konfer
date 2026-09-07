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
        attributionTakesRoom: Bool = false
    ) -> [SubtitleCue] {
        meeting.keptUtterances.flatMap { utterance in
            let speaker = meeting.displayName(for: utterance.speakerId)
            let reserved = attributionTakesRoom ? attribution(for: speaker).count : 0

            return split(utterance, firstCueBudget: maximumCharacters - reserved)
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
        }
    }

    /// How SubRip writes a speaker in front of their words.
    static func attribution(for speaker: String) -> String { "\(speaker): " }

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

    static func webVTT(for meeting: Meeting) -> String {
        var out = "WEBVTT\n"

        for (index, cue) in cues(for: meeting).enumerated() {
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

    static func srt(for meeting: Meeting) -> String {
        var out = ""

        for (index, cue) in cues(for: meeting, attributionTakesRoom: true).enumerated() {
            if index > 0 { out += "\n" }
            out += "\(index + 1)\n"
            out += "\(Timecode.subtitle(cue.start, decimalSeparator: ","))"
            out += " --> "
            out += "\(Timecode.subtitle(cue.end, decimalSeparator: ","))\n"

            // SubRip has no markup and no voice tag, so the name goes in front
            // of the words the way a script writes it — and is wrapped with
            // them, since on screen it is simply more text on the line.
            if let speaker = cue.speaker {
                out += "\(wrapped(attribution(for: speaker) + cue.text))\n"
            } else {
                out += "\(wrapped(cue.text))\n"
            }
        }

        return out
    }
}
