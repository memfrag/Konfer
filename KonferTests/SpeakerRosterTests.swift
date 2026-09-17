//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import FluidAudio
@testable import Konfer

/// The roster is the meeting's list of people, and a diarizer cluster is only a
/// person once something was said by it. The case behind these: a call played
/// over speakers bleeds into the microphone, the microphone side is diarized on
/// its own, and the far end comes back as a cluster "in the room" that every
/// word was then correctly attributed away from.
struct SpeakerRosterTests {

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

    private func turn(_ speakerId: String, _ start: TimeInterval, _ end: TimeInterval) -> Utterance {
        Utterance(speakerId: speakerId, start: start, end: end, text: "words")
    }

    @Test("A cluster nothing was attributed to is not a person")
    func unheardClusterIsNotASpeaker() {
        let room = DiarizedSide(side: .microphone, segments: [
            segment("Speaker 1", 0, 5),
            // The far end, heard through the speakers and clustered on its own.
            segment("Speaker 2", 6, 10)
        ])
        let call = DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 6, 10)])

        // Every word from 6 s on was louder on the call, so that is where they
        // went — the microphone's second cluster keeps nothing.
        let labels = TranscriptionPipeline.makeSpeakerLabels(
            sides: [room, call],
            utterances: [turn("mic:Speaker 1", 0, 5), turn("sys:Speaker 1", 6, 10)]
        )

        #expect(labels.map(\.id) == ["mic:Speaker 1", "sys:Speaker 1"])
        #expect(!labels.contains { $0.id == "mic:Speaker 2" })
    }

    @Test("Dropping an unheard cluster leaves the numbering without a gap")
    func numberingHasNoGap() {
        let room = DiarizedSide(side: .microphone, segments: [
            segment("Speaker 1", 0, 2),
            // Bleed clustered between the two people who do speak, so a naive
            // pass would number the real second speaker 3.
            segment("Speaker 2", 3, 4)
        ])
        let call = DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 5, 9)])

        let labels = TranscriptionPipeline.makeSpeakerLabels(
            sides: [room, call],
            utterances: [turn("mic:Speaker 1", 0, 2), turn("sys:Speaker 1", 5, 9)]
        )

        #expect(labels.map(\.name) == ["Speaker 1", "Speaker 2"])
        #expect(labels.first { $0.name == "Speaker 2" }?.side == .systemAudio)
    }

    @Test("A speaker who was heard keeps their side, embedding and duration")
    func heardSpeakerKeepsEverything() {
        let call = DiarizedSide(side: .systemAudio, segments: [segment("Speaker 1", 2, 6)])
        let labels = TranscriptionPipeline.makeSpeakerLabels(
            sides: [call],
            utterances: [turn("sys:Speaker 1", 2, 6)]
        )

        let speaker = labels.first
        #expect(labels.count == 1)
        #expect(speaker?.side == .systemAudio)
        #expect(speaker?.embedding == [1, 0, 0])
        #expect(speaker?.totalDuration == 4)
    }

    @Test("Words outside every segment still have an unknown speaker to belong to")
    func unknownSpeakerSurvives() {
        let labels = TranscriptionPipeline.makeSpeakerLabels(
            sides: [DiarizedSide(side: nil, segments: [])],
            utterances: [turn(SpeakerLabel.unknownID, 0, 3)]
        )
        #expect(labels.map(\.id) == [SpeakerLabel.unknownID])
    }
}
