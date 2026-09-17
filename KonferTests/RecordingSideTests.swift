//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import FluidAudio
@testable import Konfer

/// Which side a word came from is read off the channels rather than inferred,
/// and these pin down what "read off" means: the louder side wins, a side that
/// cannot be measured costs no words, and two diarization passes that each
/// number their speakers from one never collide. Fixtures only — no models, no
/// audio, no network.
struct RecordingSideTests {

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

    /// An envelope that is loud over `speaking` and silent everywhere else,
    /// out to `seconds`.
    private func envelope(
        _ side: RecordingSide,
        speaking: ClosedRange<TimeInterval>,
        of seconds: TimeInterval
    ) -> SideEnvelope {
        let count = Int(seconds / SideEnvelope.frameDuration)
        let frames = (0..<count).map { index -> Float in
            let time = Double(index) * SideEnvelope.frameDuration
            return speaking.contains(time) ? 0.05 : 0
        }
        return SideEnvelope(side: side, frames: frames)
    }

    // MARK: - Attribution

    @Test("A word goes to the side that was louder while it was spoken")
    func loudestSideWins() {
        let envelopes = [
            envelope(.microphone, speaking: 0...5, of: 10),
            envelope(.systemAudio, speaking: 6...10, of: 10)
        ]
        let split = SideAttribution.split(
            [word("here", 1, 1.5), word("there", 7, 7.5), word("again", 2, 2.5)],
            between: envelopes
        )

        #expect(split.count == 2)
        #expect(split.first { $0.side == .microphone }?.words.map(\.word) == ["here", "again"])
        #expect(split.first { $0.side == .systemAudio }?.words.map(\.word) == ["there"])
    }

    @Test("A word spoken over the other side still goes to the louder one")
    func crossTalkGoesToTheLouderSide() {
        // What a room without headphones sounds like: the microphone hears the
        // call as well, but never as loudly as the call itself.
        let microphone = SideEnvelope(side: .microphone, frames: [0.01, 0.01, 0.01])
        let systemAudio = SideEnvelope(side: .systemAudio, frames: [0.08, 0.08, 0.08])

        let split = SideAttribution.split(
            [word("bleed", 0, 0.06)],
            between: [microphone, systemAudio]
        )
        #expect(split.count == 1)
        #expect(split.first?.side == .systemAudio)
    }

    @Test("A word in silence on both sides goes to the microphone")
    func silenceFallsToTheMicrophone() {
        let envelopes = [
            envelope(.microphone, speaking: 0...1, of: 10),
            envelope(.systemAudio, speaking: 0...1, of: 10)
        ]
        let split = SideAttribution.split([word("ghost", 8, 8.5)], between: envelopes)

        #expect(split.first?.side == .microphone)
        #expect(split.flatMap(\.words).count == 1)
    }

    @Test("A recording with one source keeps every word on it")
    func singleSideTakesEverything() {
        let split = SideAttribution.split(
            [word("one", 0, 1), word("two", 5, 6)],
            between: [envelope(.systemAudio, speaking: 0...1, of: 10)]
        )
        #expect(split.count == 1)
        #expect(split.first?.side == .systemAudio)
        #expect(split.first?.words.count == 2)
    }

    // MARK: - Rosters

    @Test("Two passes that both call someone Speaker 1 stay two people")
    func clusterIdsAreQualifiedBySide() {
        let room = DiarizedSide(side: .microphone, segments: [segment("Speaker 1", 0, 5)])
        let call = DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 6, 10)])

        #expect(room.segments[0].speakerId == "mic:Speaker 1")
        #expect(call.segments[0].speakerId == "sys:Speaker 1")
        #expect(room.segments[0].speakerId != call.segments[0].speakerId)
    }

    @Test("A file with one source keeps the diarizer's own ids")
    func unsidedIdsAreLeftAlone() {
        let only = DiarizedSide(side: nil, segments: [segment("Speaker 1", 0, 5)])
        #expect(only.segments[0].speakerId == "Speaker 1")
    }

    // MARK: - Alignment across sides

    @Test("A voice on the call is never merged with a voice in the room")
    func sidesAreAlignedSeparately() {
        // Both passes found one speaker and both called it "Speaker 1"; only
        // the side keeps them apart.
        let sides = [
            DiarizedSide(side: .microphone, segments: [segment("Speaker 1", 0, 5)]),
            DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 0, 10)])
        ]
        let envelopes = [
            envelope(.microphone, speaking: 0...5, of: 10),
            envelope(.systemAudio, speaking: 6...10, of: 10)
        ]
        let words = [
            word("In", 1, 1.4), word("the", 1.4, 1.8), word("room.", 1.8, 2.2),
            word("On", 7, 7.4), word("the", 7.4, 7.8), word("call.", 7.8, 8.2)
        ]

        let turns = SpeakerAligner.align(words: words, across: sides, envelopes: envelopes)

        #expect(turns.count == 2)
        #expect(turns[0].speakerId == "mic:Speaker 1")
        #expect(turns[0].text == "In the room.")
        #expect(turns[1].speakerId == "sys:Speaker 1")
        #expect(turns[1].text == "On the call.")
    }

    @Test("Turns from both sides come back in the order they were spoken")
    func turnsAreMergedInTime() {
        let sides = [
            DiarizedSide(side: .microphone, segments: [segment("Speaker 1", 0, 10)]),
            DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 0, 10)])
        ]
        // The room has the floor, except between 3 s and 5 s.
        let envelopes = [
            envelope(.microphone, speaking: 0...3, of: 10),
            envelope(.systemAudio, speaking: 3...5, of: 10)
        ]
        let words = [
            word("First", 0.5, 1.0),
            word("second", 3.5, 4.0),
            word("third", 6.0, 6.5)
        ]

        let turns = SpeakerAligner.align(words: words, across: sides, envelopes: envelopes)

        #expect(turns.map(\.text) == ["First", "second", "third"])
        #expect(turns.map(\.speakerId) == ["mic:Speaker 1", "sys:Speaker 1", "mic:Speaker 1"])
    }

    @Test("Words are never lost when the sides cannot be measured")
    func unmeasurableSidesStillTranscribe() {
        let sides = [
            DiarizedSide(side: .microphone, segments: [segment("Speaker 1", 0, 5)]),
            DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 6, 10)])
        ]
        let turns = SpeakerAligner.align(
            words: [word("still", 1, 1.5), word("here", 7, 7.5)],
            across: sides,
            envelopes: []
        )
        #expect(turns.flatMap { $0.words ?? [] }.map(\.word) == ["still", "here"])
    }

    @Test("A side the diarizer found nobody on keeps its words anyway")
    func wordsSurviveAnEmptySide() {
        let sides = [
            DiarizedSide(side: .microphone, segments: [segment("Speaker 1", 0, 5)]),
            DiarizedSide(side: .systemAudio, segments: [])
        ]
        let envelopes = [
            envelope(.microphone, speaking: 0...5, of: 10),
            envelope(.systemAudio, speaking: 6...10, of: 10)
        ]
        let turns = SpeakerAligner.align(
            words: [word("room", 1, 1.5), word("call", 7, 7.5)],
            across: sides,
            envelopes: envelopes
        )

        #expect(turns.count == 2)
        #expect(turns[0].speakerId == "mic:Speaker 1")
        #expect(turns[1].speakerId == SpeakerLabel.unknownID)
    }
}
