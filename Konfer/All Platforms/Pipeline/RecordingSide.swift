//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Accelerate
import AVFoundation
import FluidAudio
import Foundation

// MARK: - RecordingSide

/// Which of a recording's two sources a voice came from.
///
/// A Konfer recording keeps the microphone on channel 0 and system audio on
/// channel 1 — see ``TwoChannelWriter`` — and that separation is not a detail
/// of the file format, it is knowledge. Which side a word came from is not
/// inferred from anything: it is read off the channel it was loud on, and the
/// channels are the ground truth. The diarizer never has to work out that the
/// people on the call are not the people in the room.
///
/// Absent on meetings transcribed from an ordinary file, and on every meeting
/// written before this existed.
nonisolated enum RecordingSide: String, Codable, CaseIterable, Sendable {

    /// Channel 0: the microphone, so the room this Mac is in.
    case microphone

    /// Channel 1: what the Mac played, so the far end of a call.
    case systemAudio

    var channel: Int {
        switch self {
        case .microphone: 0
        case .systemAudio: 1
        }
    }

    var displayName: String {
        switch self {
        case .microphone: "In the room"
        case .systemAudio: "On the call"
        }
    }

    var symbolName: String {
        switch self {
        case .microphone: "mic"
        case .systemAudio: "speaker.wave.2"
        }
    }

    /// Prefix for roster ids, so the two diarization passes — each of which
    /// numbers its own clusters from one — cannot collide on "Speaker 1".
    var idPrefix: String {
        switch self {
        case .microphone: "mic"
        case .systemAudio: "sys"
        }
    }

    /// The roster id a cluster from this side is filed under.
    func qualified(_ speakerId: String) -> String {
        "\(idPrefix):\(speakerId)"
    }
}

// MARK: - DiarizedSide

/// One source's speakers, as diarization found them.
///
/// Each side is diarized on its own rather than the two being separated
/// afterwards, because a clusterer given both at once can merge a voice in the
/// room with a voice on the call, and the embedding it then carries into the
/// enrollment roster belongs to neither of them. Per side it cannot: the two
/// passes never see each other's audio. That costs one extra diarization —
/// 28.9 s on a 1 h 17 m meeting, against the 585 s the same meeting spends
/// being transcribed.
nonisolated struct DiarizedSide: Sendable {

    /// Which source these came from, or nil for a recording with one source
    /// and no side worth naming.
    let side: RecordingSide?

    /// Segments whose speaker ids are already qualified by side, so two
    /// passes that each number their clusters from one cannot collide.
    let segments: [TimedSpeakerSegment]

    /// Renames a pass's clusters into the meeting's roster namespace.
    init(side: RecordingSide?, segments: [TimedSpeakerSegment]) {
        self.side = side
        guard let side else {
            self.segments = segments
            return
        }
        self.segments = segments.map { segment in
            TimedSpeakerSegment(
                speakerId: side.qualified(segment.speakerId),
                embedding: segment.embedding,
                startTimeSeconds: segment.startTimeSeconds,
                endTimeSeconds: segment.endTimeSeconds,
                qualityScore: segment.qualityScore
            )
        }
    }
}

// MARK: - SideEnvelope

/// How loud one side is, frame by frame.
///
/// Built once per side and then asked, for each word the ASR produced, whether
/// that word was this side speaking. Cheap enough to be worth its own pass:
/// an hour is 180,000 floats.
nonisolated struct SideEnvelope: Sendable {

    /// 20 ms — short enough to sit inside the shortest word anyone says, long
    /// enough that a single click cannot carry a frame on its own.
    static let frameDuration: TimeInterval = 0.02

    let side: RecordingSide

    /// Mean square per frame. Kept squared rather than rooted: the only thing
    /// ever done with it is compare it against the other side.
    let frames: [Float]

    /// Mean energy across a span, or zero when the span falls outside the
    /// recording.
    func energy(from start: TimeInterval, to end: TimeInterval) -> Float {
        let first = max(0, Int(start / Self.frameDuration))
        let last = min(frames.count - 1, Int(end / Self.frameDuration))
        guard first <= last, last >= 0, first < frames.count else { return 0 }
        var total: Float = 0
        frames.withUnsafeBufferPointer { buffer in
            vDSP_meanv(
                buffer.baseAddress! + first, 1,
                &total,
                vDSP_Length(last - first + 1)
            )
        }
        return total
    }

    /// Measures one mono file.
    static func measure(_ url: URL, side: RecordingSide) throws -> SideEnvelope {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        let perFrame = max(1, Int(rate * frameDuration))

        var frames: [Float] = []
        frames.reserveCapacity(Int(Double(file.length) / Double(perFrame)) + 1)

        var carry: [Float] = []
        try AudioBuffers.forEach(in: file) { buffer in
            guard let data = buffer.floatChannelData else { return }
            carry += Array(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
            var offset = 0
            while offset + perFrame <= carry.count {
                var mean: Float = 0
                carry.withUnsafeBufferPointer { samples in
                    vDSP_measqv(samples.baseAddress! + offset, 1, &mean, vDSP_Length(perFrame))
                }
                frames.append(mean)
                offset += perFrame
            }
            carry.removeFirst(offset)
        }
        if !carry.isEmpty {
            var mean: Float = 0
            vDSP_measqv(carry, 1, &mean, vDSP_Length(carry.count))
            frames.append(mean)
        }

        return SideEnvelope(side: side, frames: frames)
    }
}

// MARK: - Attribution

/// Splits what the ASR heard between the sides that were recorded.
nonisolated enum SideAttribution {

    /// Each word filed under the side that was louder while it was spoken.
    ///
    /// Louder wins outright, with no tie-break band, and the asymmetry of the
    /// two sources is why that is safe. System audio is captured digitally, so
    /// nothing said in the room can ever appear on it; the microphone, on the
    /// other hand, hears the speakers whenever the user isn't on headphones.
    /// Every ambiguous word is therefore the same case — system audio bleeding
    /// into the microphone — and in that case the side it bleeds *from* is the
    /// louder one.
    ///
    /// A word whose span is silent on both sides, which is what an ASR
    /// hallucination in a gap looks like, goes to the microphone: the side the
    /// person running the recording is on.
    static func split(
        _ words: [WordSpan],
        between envelopes: [SideEnvelope]
    ) -> [(side: RecordingSide, words: [WordSpan])] {

        guard envelopes.count > 1 else {
            return envelopes.first.map { [($0.side, words)] } ?? []
        }

        var grouped: [RecordingSide: [WordSpan]] = [:]
        for word in words {
            let loudest = envelopes.max {
                $0.energy(from: word.start, to: word.end)
                    < $1.energy(from: word.start, to: word.end)
            }
            grouped[loudest?.side ?? .microphone, default: []].append(word)
        }

        // Ordered, so a transcript's speaker numbering doesn't depend on
        // dictionary iteration order.
        return RecordingSide.allCases.compactMap { side in
            grouped[side].map { (side, $0) }
        }
    }
}

// MARK: - Reading

/// Walks an audio file a buffer at a time.
///
/// Each read is clamped to what is left rather than always asking for a full
/// buffer: `read(into:)` at the end of a compressed file throws on some formats
/// instead of returning zero frames, which turns the last buffer of a perfectly
/// good recording into a failed import.
nonisolated enum AudioBuffers {

    static let capacity: AVAudioFrameCount = 16_384

    /// - Parameter within: The frames to read, or nil for the whole file.
    static func forEach(
        in file: AVAudioFile,
        within range: Range<AVAudioFramePosition>? = nil,
        _ body: (AVAudioPCMBuffer) throws -> Void
    ) throws {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: capacity
        ) else { return }

        let start = range?.lowerBound ?? 0
        let end = min(range?.upperBound ?? file.length, file.length)
        guard start < end else { return }

        file.framePosition = start
        while file.framePosition < end {
            let remaining = AVAudioFrameCount(
                min(AVAudioFramePosition(capacity), end - file.framePosition)
            )
            try file.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else { break }
            try body(buffer)
        }
    }
}
