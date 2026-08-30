//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import FluidAudio
@testable import Snoopy

/// The merge is the one piece FluidAudio doesn't provide, so it's the piece
/// worth testing. These run on fixtures — no models, no audio, no network.
struct SpeakerAlignerTests {

    // MARK: - Fixtures

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> WordSpan {
        WordSpan(word: text, start: start, end: end)
    }

    private func segment(
        _ speaker: String,
        _ start: Float,
        _ end: Float
    ) -> TimedSpeakerSegment {
        TimedSpeakerSegment(
            speakerId: speaker,
            embedding: [1, 0, 0],
            startTimeSeconds: start,
            endTimeSeconds: end,
            qualityScore: 1
        )
    }

    // MARK: - Tests

    @Test("Words are grouped into one turn per speaker")
    func groupsWordsBySpeaker() {
        let words = [
            word("Hej", 0.0, 0.4),
            word("allihopa.", 0.4, 1.0),
            word("Hello", 2.0, 2.4),
            word("everyone.", 2.4, 3.0)
        ]
        let segments = [segment("A", 0, 1.2), segment("B", 1.8, 3.2)]

        let turns = SpeakerAligner.align(words: words, segments: segments)

        #expect(turns.count == 2)
        #expect(turns[0].speakerId == "A")
        #expect(turns[0].text == "Hej allihopa.")
        #expect(turns[1].speakerId == "B")
        #expect(turns[1].text == "Hello everyone.")
    }

    @Test("A word straddling a boundary goes to the speaker it overlaps most")
    func straddlingWordFollowsGreaterOverlap() {
        // 0.9–1.3: 0.1s inside A, 0.3s inside B.
        let words = [word("gränsfall", 0.9, 1.3)]
        let segments = [segment("A", 0, 1.0), segment("B", 1.0, 2.0)]

        let turns = SpeakerAligner.align(words: words, segments: segments)

        #expect(turns.count == 1)
        #expect(turns[0].speakerId == "B")
    }

    @Test("A word in a diarization gap joins the nearest speaker")
    func gapWordFallsBackToNearestSegment() {
        // Nothing covers 1.2–1.4; A ends at 1.0, B starts at 3.0.
        let words = [word("mellanrum", 1.2, 1.4)]
        let segments = [segment("A", 0, 1.0), segment("B", 3.0, 4.0)]

        let turns = SpeakerAligner.align(words: words, segments: segments)

        #expect(turns.count == 1)
        #expect(turns[0].speakerId == "A")
    }

    @Test("A single-word turn survives between two longer ones")
    func singleWordTurn() {
        let words = [
            word("So", 0.0, 0.3),
            word("Ja.", 1.1, 1.4),
            word("anyway", 2.1, 2.6)
        ]
        let segments = [
            segment("A", 0, 0.5),
            segment("B", 1.0, 1.5),
            segment("A", 2.0, 2.8)
        ]

        let turns = SpeakerAligner.align(words: words, segments: segments)

        #expect(turns.count == 3)
        #expect(turns.map(\.speakerId) == ["A", "B", "A"])
        #expect(turns[1].text == "Ja.")
    }

    @Test("With no segments every word becomes one unknown-speaker turn")
    func noSegmentsProducesUnknownSpeaker() {
        let words = [word("Ett", 0.0, 0.3), word("två", 0.4, 0.8)]

        let turns = SpeakerAligner.align(words: words, segments: [])

        #expect(turns.count == 1)
        #expect(turns[0].speakerId == SpeakerLabel.unknownID)
        #expect(turns[0].text == "Ett två")
    }

    @Test("No words means no turns, whatever the diarizer found")
    func noWordsProducesNoTurns() {
        #expect(SpeakerAligner.align(words: [], segments: [segment("A", 0, 5)]).isEmpty)
    }

    @Test("A long silence splits one speaker's run into separate turns")
    func longSilenceSplitsTurns() {
        let words = [
            word("Först", 0.0, 0.5),
            word("sedan", 5.0, 5.5)   // 4.5s gap, well over the 1.5s threshold
        ]
        let segments = [segment("A", 0, 6)]

        let turns = SpeakerAligner.align(words: words, segments: segments)

        #expect(turns.count == 2)
        #expect(turns.allSatisfy { $0.speakerId == "A" })
    }

    @Test("Punctuation is joined tight, words are spaced")
    func punctuationJoinsWithoutSpace() {
        let words = [word("Hej", 0, 0.3), word(",", 0.3, 0.35), word("du", 0.4, 0.6)]

        let turns = SpeakerAligner.align(words: words, segments: [segment("A", 0, 1)])

        #expect(turns[0].text == "Hej, du")
    }

    @Test("Turn bounds come from its first and last word")
    func turnBoundsMatchWords() {
        let words = [word("a", 1.0, 1.5), word("b", 1.6, 2.25)]

        let turns = SpeakerAligner.align(words: words, segments: [segment("A", 0, 5)])

        #expect(turns[0].start == 1.0)
        #expect(turns[0].end == 2.25)
        #expect(turns[0].words?.count == 2)
    }
}
