//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - TranscriptMatch

/// One occurrence of a search query in a meeting.
///
/// Positions are plain character offsets into ``Utterance/text`` rather than
/// `String.Index`, because a match outlives the string it was found in: the
/// transcript can be edited between finding a match and replacing it.
nonisolated struct TranscriptMatch: Identifiable, Hashable, Sendable {

    let utteranceID: UUID

    /// Characters from the start of the utterance's text.
    let offset: Int
    let length: Int

    var id: String { "\(utteranceID.uuidString)-\(offset)" }

    var range: Range<Int> { offset..<(offset + length) }
}

// MARK: - TranscriptSearch

/// Finding and replacing text across a meeting's turns.
///
/// Kept apart from the view because the interesting part is not the find bar:
/// it is knowing whether a replacement can keep the recording's word timings,
/// which is the difference between a transcript you can still click through
/// and one you cannot.
nonisolated enum TranscriptSearch {

    // MARK: - Finding

    /// Every occurrence of `query`, in reading order.
    ///
    /// Case- and diacritic-insensitive, so searching a Swedish transcript for
    /// "aker" finds "åker" — the kind of thing you are searching for precisely
    /// because you are not sure how the model spelled it.
    static func matches(for query: String, in utterances: [Utterance]) -> [TranscriptMatch] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        var matches: [TranscriptMatch] = []
        for utterance in utterances {
            let text = utterance.text
            var searchStart = text.startIndex

            while searchStart < text.endIndex,
                  let found = text.range(
                      of: query,
                      options: [.caseInsensitive, .diacriticInsensitive],
                      range: searchStart..<text.endIndex
                  ) {
                matches.append(
                    TranscriptMatch(
                        utteranceID: utterance.id,
                        offset: text.distance(from: text.startIndex, to: found.lowerBound),
                        length: text.distance(from: found.lowerBound, to: found.upperBound)
                    )
                )
                // Advance by one character rather than by the match, so
                // overlapping occurrences ("aa" in "aaa") are all found.
                searchStart = text.index(after: found.lowerBound)
            }
        }
        return matches
    }

    // MARK: - Where the words sit

    /// Where each word span lands in the joined text of an utterance.
    ///
    /// ``SpeakerAligner/joined(_:)`` is what built that text, so this walks the
    /// same rule rather than guessing at it — including the punctuation that
    /// hugs the word before it.
    ///
    /// - Returns: One range per word span, in order. Empty spans are skipped,
    ///   so the result is not index-aligned with `words`; each element carries
    ///   the index it came from.
    static func wordRanges(in words: [WordSpan]) -> [(index: Int, range: Range<Int>)] {
        var ranges: [(index: Int, range: Range<Int>)] = []
        var offset = 0

        for (index, word) in words.enumerated() {
            let piece = word.word
            guard !piece.isEmpty else { continue }
            if offset > 0 {
                offset += SpeakerAligner.spacing(before: piece).count
            }
            ranges.append((index, offset..<(offset + piece.count)))
            offset += piece.count
        }
        return ranges
    }

    /// The single word span a match falls inside, if it falls inside exactly
    /// one.
    ///
    /// A match spanning two words, or the space between them, has no answer
    /// here — and that is the case where a replacement cannot keep its
    /// timings, because the words being replaced no longer map one to one onto
    /// the words the model timed.
    static func enclosingWord(
        of match: TranscriptMatch,
        in words: [WordSpan]
    ) -> (index: Int, range: Range<Int>)? {
        wordRanges(in: words).first {
            $0.range.lowerBound <= match.offset
                && match.offset + match.length <= $0.range.upperBound
        }
    }

    // MARK: - Replacing

    /// What replacing a match would cost.
    enum ReplacementKind: Equatable {
        /// The match sits inside one word, so that word's text can be
        /// rewritten and its start and end kept. Playback still highlights it.
        case keepsTimings
        /// The match spans more than one word, so the turn's timings have to
        /// go and it is marked as edited by hand.
        case dropsTimings
    }

    /// Whether replacing this match would keep the turn's word timings.
    static func replacementKind(
        of match: TranscriptMatch,
        in utterance: Utterance
    ) -> ReplacementKind {
        guard let words = utterance.words,
              enclosingWord(of: match, in: words) != nil else { return .dropsTimings }
        return .keepsTimings
    }
}
