//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Corrections a person can make to a finished transcript.
///
/// Both the diarizer and the recogniser make mistakes often enough that a
/// read-only transcript would just send people to a text editor. These
/// operations are deliberately literal: nothing merges or re-groups turns
/// behind the user's back, so split-then-reassign behaves the way it looks.
///
/// Which neighbour a turn is merged with.
nonisolated enum MergeDirection {
    case previous
    case next
}

nonisolated extension Meeting {

    // MARK: - Speakers

    mutating func renameSpeaker(_ speakerId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = speakers.firstIndex(where: { $0.id == speakerId })
        else { return }

        speakers[index].name = trimmed
        speakers[index].isNamed = true
        speakers[index].suggestion = nil
    }

    /// Folds one cluster into another: they were the same person.
    ///
    /// This is the fix for the diarizer's most common failure, splitting one
    /// voice across two clusters. Embeddings are combined weighted by how much
    /// each cluster actually spoke.
    mutating func mergeSpeaker(_ source: String, into destination: String) {
        guard source != destination,
              let sourceIndex = speakers.firstIndex(where: { $0.id == source }),
              let destinationIndex = speakers.firstIndex(where: { $0.id == destination })
        else { return }

        let absorbed = speakers[sourceIndex]
        let keeper = speakers[destinationIndex]

        speakers[destinationIndex].embedding = Self.weightedMean(
            (keeper.embedding, keeper.totalDuration),
            (absorbed.embedding, absorbed.totalDuration)
        )
        speakers[destinationIndex].totalDuration += absorbed.totalDuration
        speakers.remove(at: sourceIndex)

        for index in utterances.indices where utterances[index].speakerId == source {
            utterances[index].speakerId = destination
        }
    }

    // MARK: - Utterances

    /// Moves a single misattributed turn to another speaker.
    mutating func reassign(_ utteranceID: UUID, to speakerId: String) {
        guard speakers.contains(where: { $0.id == speakerId }),
              let index = utterances.firstIndex(where: { $0.id == utteranceID })
        else { return }
        utterances[index].speakerId = speakerId
    }

    /// Splits a turn in two at a word boundary, for a speaker change the
    /// diarizer missed mid-sentence.
    ///
    /// - Parameter wordIndex: Index of the first word of the second half.
    ///   Must be strictly inside the turn.
    /// - Returns: The id of the newly created second half, if the split
    ///   happened. Splitting needs word timings, so an edited turn can't be
    ///   split — its words no longer correspond to anything that was heard.
    @discardableResult
    mutating func splitUtterance(_ utteranceID: UUID, atWordIndex wordIndex: Int) -> UUID? {
        guard let index = utterances.firstIndex(where: { $0.id == utteranceID }),
              let words = utterances[index].words,
              wordIndex > 0, wordIndex < words.count
        else { return nil }

        let head = Array(words[..<wordIndex])
        let tail = Array(words[wordIndex...])
        let original = utterances[index]

        let first = Utterance(
            id: original.id,
            speakerId: original.speakerId,
            start: head[0].start,
            end: head[head.count - 1].end,
            text: SpeakerAligner.joined(head),
            words: head
        )
        let second = Utterance(
            speakerId: original.speakerId,
            start: tail[0].start,
            end: tail[tail.count - 1].end,
            text: SpeakerAligner.joined(tail),
            words: tail
        )

        utterances[index] = first
        utterances.insert(second, at: index + 1)
        return second.id
    }

    /// Joins a turn with the one before or after it — the inverse of splitting,
    /// and the fix for a turn the diarizer broke in two.
    ///
    /// The **earlier** of the two turns wins: the merged turn keeps its id and
    /// its speaker. Merging across a speaker change is allowed, since that is
    /// exactly the correction being made; reassign afterwards if the surviving
    /// speaker is the wrong one.
    ///
    /// The absorbed speaker stays on the roster even if that was their last
    /// line — dropping them would throw away the voice embedding and the
    /// ability to reassign a line back to them.
    ///
    /// - Returns: The id of the surviving turn, or `nil` at the ends of the
    ///   transcript where there is nothing to merge with.
    @discardableResult
    mutating func mergeUtterance(
        _ utteranceID: UUID,
        with neighbour: MergeDirection
    ) -> UUID? {
        guard let index = utterances.firstIndex(where: { $0.id == utteranceID }) else {
            return nil
        }

        let firstIndex: Int
        switch neighbour {
        case .previous:
            guard index > 0 else { return nil }
            firstIndex = index - 1
        case .next:
            guard index + 1 < utterances.count else { return nil }
            firstIndex = index
        }

        let first = utterances[firstIndex]
        let second = utterances[firstIndex + 1]

        // Word timings survive only if both halves still have them. If either
        // was edited, the merged text no longer maps to anything the model
        // timed, so the whole turn falls back to turn-level highlighting.
        let words: [WordSpan]?
        if let leading = first.words, let trailing = second.words {
            words = leading + trailing
        } else {
            words = nil
        }

        let text: String
        if let words {
            text = SpeakerAligner.joined(words)
        } else if first.text.isEmpty || second.text.isEmpty {
            text = first.text.isEmpty ? second.text : first.text
        } else {
            text = first.text + SpeakerAligner.spacing(before: second.text) + second.text
        }

        utterances[firstIndex] = Utterance(
            id: first.id,
            speakerId: first.speakerId,
            start: min(first.start, second.start),
            end: max(first.end, second.end),
            text: text,
            words: words,
            isEdited: first.isEdited || second.isEdited
        )
        utterances.remove(at: firstIndex + 1)
        return first.id
    }

    /// Replaces a turn's text.
    ///
    /// The turn's own start and end stay correct — the boundary didn't move —
    /// but word timings are dropped, because the edited words are no longer
    /// the ones the model timed. Playback falls back to highlighting the whole
    /// turn for that line.
    mutating func editText(of utteranceID: UUID, to text: String) {
        guard let index = utterances.firstIndex(where: { $0.id == utteranceID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != utterances[index].text else { return }

        utterances[index].text = trimmed
        utterances[index].words = nil
        utterances[index].isEdited = true
    }

    // MARK: - Search and replace

    /// Replaces one search match, keeping the recording's word timings where
    /// the match allows it.
    ///
    /// The point of the distinction: a transcript's word timings are what make
    /// clicking a word seek to it, and they cannot be recovered once dropped —
    /// only re-transcribing brings them back. Fixing a name the model
    /// consistently misheard should not cost that, and it doesn't have to,
    /// because such a fix lives inside a single word: rewrite that word's text
    /// and its start and end still describe when it was said.
    ///
    /// A match spanning several words is a different matter. There is no
    /// honest way to time the replacement, so the turn falls back to the same
    /// terms as a hand edit — timings dropped, marked as edited.
    ///
    /// - Returns: What it cost, or nil if the match no longer fits the text.
    @discardableResult
    mutating func replace(
        _ match: TranscriptMatch,
        with replacement: String
    ) -> TranscriptSearch.ReplacementKind? {

        guard let index = utterances.firstIndex(where: { $0.id == match.utteranceID })
        else { return nil }

        let utterance = utterances[index]
        let text = utterance.text

        // The transcript may have changed under a match found earlier.
        guard match.offset >= 0, match.offset + match.length <= text.count
        else { return nil }

        if let words = utterance.words,
           let word = TranscriptSearch.enclosingWord(of: match, in: words) {

            // Rewrite just this word, and rebuild the text from the words so
            // the two cannot drift apart.
            // A span's word and its timings are both set at transcription and
            // immutable after, so this is a new span carrying the old timings
            // rather than a mutation of the old one.
            var updated = words
            let old = words[word.index]
            updated[word.index] = WordSpan(
                word: Self.replacing(
                    in: old.word,
                    offset: match.offset - word.range.lowerBound,
                    length: match.length,
                    with: replacement
                ),
                start: old.start,
                end: old.end
            )

            // A replacement that empties a word would leave a span timing
            // nothing, so drop it rather than keep a ghost.
            updated.removeAll { $0.word.isEmpty }

            utterances[index].words = updated
            utterances[index].text = SpeakerAligner.joined(updated)
            return .keepsTimings
        }

        utterances[index].text = Self.replacing(
            in: text, offset: match.offset, length: match.length, with: replacement
        )
        utterances[index].words = nil
        utterances[index].isEdited = true
        return .dropsTimings
    }

    /// Replaces every occurrence of `query`, back to front so that earlier
    /// offsets stay valid as the text changes underneath them.
    ///
    /// - Returns: How many turns kept their timings, and how many lost them.
    @discardableResult
    mutating func replaceAll(
        _ query: String,
        with replacement: String
    ) -> (kept: Int, dropped: Int) {

        var kept = 0
        var dropped = 0

        for match in TranscriptSearch.matches(for: query, in: utterances).reversed() {
            switch replace(match, with: replacement) {
            case .keepsTimings: kept += 1
            case .dropsTimings: dropped += 1
            case nil: break
            }
        }
        return (kept, dropped)
    }

    /// Character-offset substring replacement, since matches carry offsets
    /// rather than indices into a string that may have moved on.
    private static func replacing(
        in text: String,
        offset: Int,
        length: Int,
        with replacement: String
    ) -> String {
        guard offset >= 0, offset + length <= text.count else { return text }
        let start = text.index(text.startIndex, offsetBy: offset)
        let end = text.index(start, offsetBy: length)
        return text.replacingCharacters(in: start..<end, with: replacement)
    }

    // MARK: - Helpers

    private static func weightedMean(
        _ lhs: ([Float], TimeInterval),
        _ rhs: ([Float], TimeInterval)
    ) -> [Float] {
        guard lhs.0.count == rhs.0.count, !lhs.0.isEmpty else {
            return lhs.0.isEmpty ? rhs.0 : lhs.0
        }
        let lhsWeight = Float(max(lhs.1, 0))
        let rhsWeight = Float(max(rhs.1, 0))
        let total = lhsWeight + rhsWeight
        guard total > 0 else { return lhs.0 }

        return zip(lhs.0, rhs.0).map { ($0 * lhsWeight + $1 * rhsWeight) / total }
    }
}
