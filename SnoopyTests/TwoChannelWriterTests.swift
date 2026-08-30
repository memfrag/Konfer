//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AVFoundation
import Foundation
@testable import Snoopy

/// The recorder's whole value is that the two sides stay apart. These check the
/// part that can be checked without a microphone in the room.
@MainActor
struct TwoChannelWriterTests {

    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("snoopy-test-\(UUID().uuidString).m4a")
    }

    private func read(_ url: URL) throws -> (frames: Int, left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let frames = Int(buffer.frameLength)
        let channels = buffer.floatChannelData!
        return (
            frames,
            Array(UnsafeBufferPointer(start: channels[0], count: frames)),
            Array(UnsafeBufferPointer(start: channels[1], count: frames))
        )
    }

    @Test("The microphone lands on the left and system audio on the right")
    func channelsStaySeparate() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TwoChannelWriter(url: url)
        writer.appendMicrophone([Float](repeating: 0.5, count: 4800))
        writer.appendSystemAudio([Float](repeating: -0.25, count: 4800))
        writer.finish()

        let audio = try read(url)
        #expect(audio.frames == 4800)
        // Lossless, so these should come back as written rather than merely close.
        #expect(audio.left.allSatisfy { abs($0 - 0.5) < 0.001 })
        #expect(audio.right.allSatisfy { abs($0 + 0.25) < 0.001 })
    }

    @Test("A side that never arrives becomes silence, not a stall")
    func missingSideBecomesSilence() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TwoChannelWriter(url: url)
        writer.markSilent(.system)
        writer.appendMicrophone([Float](repeating: 0.5, count: 2400))
        writer.finish()

        let audio = try read(url)
        #expect(audio.frames == 2400)
        #expect(audio.left.allSatisfy { $0 > 0.4 })
        #expect(audio.right.allSatisfy { $0 == 0 })
    }

    @Test("Sides arriving at different rates stay aligned")
    func unevenArrivalStaysAligned() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TwoChannelWriter(url: url)
        // The microphone runs ahead by three buffers before the other side
        // delivers anything — exactly what happens while a call is connecting.
        for _ in 0..<3 { writer.appendMicrophone([Float](repeating: 0.5, count: 1000)) }
        writer.appendSystemAudio([Float](repeating: -0.5, count: 3000))
        writer.finish()

        let audio = try read(url)
        #expect(audio.frames == 3000)
        // Sample 0 of each channel must be sample 0 of each source: if the
        // writer had emitted the microphone early, the right channel would be
        // padded with silence and the two would be offset for good.
        #expect(abs(audio.left[0] - 0.5) < 0.001)
        #expect(abs(audio.right[0] + 0.5) < 0.001)
        #expect(abs(audio.right[2999] + 0.5) < 0.001)
    }

    @Test("Levels are reported per channel and reset when read")
    func levelsArePerChannel() throws {
        let url = makeURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try TwoChannelWriter(url: url)
        writer.appendMicrophone([0.8, -0.2])
        writer.appendSystemAudio([0.1, -0.05])

        let levels = writer.consumeLevels()
        #expect(abs(levels.microphone - 0.8) < 0.001)
        #expect(abs(levels.system - 0.1) < 0.001)

        // Peaks are since the last read, so a quiet moment reads as quiet.
        let next = writer.consumeLevels()
        #expect(next.microphone == 0)
        #expect(next.system == 0)
    }
}
