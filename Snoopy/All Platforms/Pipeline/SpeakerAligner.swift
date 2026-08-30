//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

/// Merges ASR word timings with diarization speaker segments.
///
/// FluidAudio ships both halves but nothing that joins them — there is no
/// combined API and no CLI command that does it. This is that join, and it is
/// the core of the app.
///
/// Every word is attributed to the speaker segment it overlaps most, then
/// consecutive words sharing a speaker are grouped into turns.
///
nonisolated enum SpeakerAligner {

    /// Silence longer than this inside one speaker's run starts a new turn.
    static let turnGapThreshold: TimeInterval = 1.5

    /// A turn longer than this may be broken at the next sentence end, so a
    /// monologue doesn't render as one unreadable block.
    static let softMaxTurnDuration: TimeInterval = 30

    /// Attributes each word to a speaker and groups the result into turns.
    ///
    /// - Parameters:
    ///   - words: Word timings from the ASR backend, in emission order.
    ///   - segments: Speaker segments from the diarizer, in any order.
    /// - Returns: Turns in transcript order. Empty if `words` is empty.
    ///
    /// If `segments` is empty every word is attributed to
    /// ``SpeakerLabel/unknownID``, which is what a degraded run looks like:
    /// a timestamped transcript with no speaker information, still worth having.
    ///
    static func align(
        words: [WordSpan],
        segments: [TimedSpeakerSegment]
    ) -> [Utterance] {

        guard !words.isEmpty else { return [] }

        // Sorting segments lets attribution walk them with a moving cursor
        // instead of scanning all of them per word. Word order is left alone:
        // FluidAudio clamps token timestamps monotonic rather than sorting, so
        // emission order — not time order — is authoritative for the text.
        let ordered = segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

        var turns: [Utterance] = []
        var current: [WordSpan] = []
        var currentSpeaker: String?
        var cursor = 0

        func flush() {
            guard let speaker = currentSpeaker, !current.isEmpty else { return }
            turns.append(makeUtterance(speakerId: speaker, words: current))
            current = []
        }

        for word in words {
            let speaker = Self.speaker(for: word, in: ordered, cursor: &cursor)

            let startsNewTurn: Bool
            if speaker != currentSpeaker {
                startsNewTurn = true
            } else if let previous = current.last,
                      word.start - previous.end > turnGapThreshold {
                startsNewTurn = true
            } else if let first = current.first,
                      word.start - first.start > softMaxTurnDuration,
                      endsSentence(current.last?.word) {
                startsNewTurn = true
            } else {
                startsNewTurn = false
            }

            if startsNewTurn {
                flush()
                currentSpeaker = speaker
            }
            current.append(word)
        }
        flush()

        return turns
    }

    // MARK: - Attribution

    /// The speaker whose segment overlaps this word most.
    ///
    /// `cursor` advances monotonically through the sorted segments so the whole
    /// pass stays linear rather than quadratic in the number of words.
    private static func speaker(
        for word: WordSpan,
        in segments: [TimedSpeakerSegment],
        cursor: inout Int
    ) -> String {

        guard !segments.isEmpty else { return SpeakerLabel.unknownID }

        // Skip segments that ended before this word began. Words arrive in
        // roughly increasing time, so the cursor rarely rewinds.
        while cursor < segments.count,
              TimeInterval(segments[cursor].endTimeSeconds) < word.start,
              cursor + 1 < segments.count {
            cursor += 1
        }

        var bestOverlap: TimeInterval = 0
        var best: String?

        var index = cursor
        while index < segments.count {
            let segment = segments[index]
            let start = TimeInterval(segment.startTimeSeconds)
            let end = TimeInterval(segment.endTimeSeconds)

            // Sorted by start time, so once a segment begins after the word
            // ends, no later segment can overlap it either.
            if start > word.end { break }

            let overlap = min(word.end, end) - max(word.start, start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = segment.speakerId
            }
            index += 1
        }

        if let best, bestOverlap > 0 { return best }

        // The word fell in a diarization gap — a pause the segmenter trimmed,
        // or speech it missed. Attribute it to whichever segment is nearest by
        // midpoint, so gap words join the turn around them rather than forming
        // spurious one-word turns.
        return nearestSpeaker(to: word, in: segments) ?? SpeakerLabel.unknownID
    }

    private static func nearestSpeaker(
        to word: WordSpan,
        in segments: [TimedSpeakerSegment]
    ) -> String? {
        let midpoint = (word.start + word.end) / 2
        var bestDistance = TimeInterval.greatestFiniteMagnitude
        var best: String?

        for segment in segments {
            let start = TimeInterval(segment.startTimeSeconds)
            let end = TimeInterval(segment.endTimeSeconds)
            let distance: TimeInterval =
                if midpoint < start { start - midpoint }
                else if midpoint > end { midpoint - end }
                else { 0 }

            if distance < bestDistance {
                bestDistance = distance
                best = segment.speakerId
            }
        }
        return best
    }

    // MARK: - Turn construction

    private static func makeUtterance(speakerId: String, words: [WordSpan]) -> Utterance {
        Utterance(
            speakerId: speakerId,
            start: words.first?.start ?? 0,
            end: words.last?.end ?? 0,
            text: joined(words),
            words: words
        )
    }

    /// Joins words into readable text, keeping punctuation tight.
    ///
    /// Parakeet v3 emits punctuation and capitalization as part of its tokens,
    /// so this only has to avoid inserting a space before a mark.
    static func joined(_ words: [WordSpan]) -> String {
        var text = ""
        for word in words {
            let piece = word.word
            guard !piece.isEmpty else { continue }
            if !text.isEmpty {
                text += spacing(before: piece)
            }
            text += piece
        }
        return text
    }

    /// The separator to put in front of `piece` when it follows another word.
    /// Empty before a mark that should hug the previous word.
    static func spacing(before piece: String) -> String {
        startsWithPunctuation(piece) ? "" : " "
    }

    private static let tightPunctuation: Set<Character> = [
        ".", ",", "!", "?", ":", ";", ")", "]", "}", "%", "…", "”", "’"
    ]

    private static func startsWithPunctuation(_ piece: String) -> Bool {
        guard let first = piece.first else { return false }
        return tightPunctuation.contains(first)
    }

    private static func endsSentence(_ word: String?) -> Bool {
        guard let last = word?.last else { return false }
        return last == "." || last == "?" || last == "!"
    }
}
