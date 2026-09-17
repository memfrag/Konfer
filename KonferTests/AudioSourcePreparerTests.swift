//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Testing
import Foundation
@testable import Konfer

/// A recording keeps the microphone on channel 0 and system audio on channel 1,
/// and every stage below the preparer reduces the file to one channel before it
/// listens to it — with an `AVAudioConverter` that keeps channel 0 and throws
/// the rest away. These pin down that the preparer folds the channels together
/// first, which is the only reason the second source is transcribed at all.
/// Synthesised tones, no models, no network.
struct AudioSourcePreparerTests {

    // MARK: - Fixtures

    /// A file with `channels.count` channels, each holding the samples given.
    /// Apple Lossless at 48 kHz, which is what the recorder writes.
    private static func write(_ channels: [[Float]]) throws -> URL {
        let frames = channels.map(\.count).max() ?? 0
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonferTest-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: 48_000.0,
            AVNumberOfChannelsKey: channels.count,
            AVEncoderBitDepthHintKey: 16,
        ])

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: AVAudioChannelCount(channels.count),
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for (index, samples) in channels.enumerated() {
            for frame in 0..<frames {
                buffer.floatChannelData![index][frame] = frame < samples.count ? samples[frame] : 0
            }
        }
        try file?.write(from: buffer)
        // An `.m4a` is only a valid file once `AVAudioFile` has closed it.
        file = nil
        return url
    }

    /// A sine at `amplitude`, silent outside `seconds`.
    private static func tone(
        amplitude: Float,
        seconds: ClosedRange<Double>,
        of total: Double
    ) -> [Float] {
        (0..<Int(total * 48_000)).map { frame in
            let time = Double(frame) / 48_000
            guard seconds.contains(time) else { return 0 }
            return amplitude * Float(sin(2 * .pi * 440 * time))
        }
    }

    /// How many files the preparer currently has in the temporary directory,
    /// which it shares with the running app — only the change across one call
    /// means anything.
    private static func temporaryFileCount() -> Int {
        let contents = try? FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path
        )
        return contents?.filter { $0.hasPrefix("Konfer-") }.count ?? 0
    }

    private static func peak(of url: URL) throws -> (channels: AVAudioChannelCount, peak: Float) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384)!
        var peak: Float = 0
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(
                min(AVAudioFramePosition(16_384), file.length - file.framePosition)
            )
            try file.read(into: buffer, frameCount: remaining)
            guard buffer.frameLength > 0 else { break }
            for channel in 0..<Int(file.processingFormat.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(buffer.floatChannelData![channel][frame]))
                }
            }
        }
        return (file.processingFormat.channelCount, peak)
    }

    // MARK: - Tests

    @Test("System audio on the second channel survives into the prepared file")
    func secondChannelIsHeard() async throws {
        // Nothing on the microphone at all: whatever reaches the pipeline can
        // only have come from channel 1.
        let source = try Self.write([
            [Float](repeating: 0, count: 48_000 * 2),
            Self.tone(amplitude: 0.5, seconds: 0.5...1.5, of: 2)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source)
        defer { prepared.cleanUp() }

        let (channels, peak) = try Self.peak(of: prepared.url)
        #expect(channels == 1)
        #expect(peak > 0.4)
    }

    @Test("Folding the channels keeps the level of the loudest one")
    func mixdownDoesNotClipOrHalve() async throws {
        // Both sides speaking at once, which summed unscaled would clip.
        let source = try Self.write([
            Self.tone(amplitude: 0.6, seconds: 0...2, of: 2),
            Self.tone(amplitude: 0.6, seconds: 0...2, of: 2)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source)
        defer { prepared.cleanUp() }

        let (_, peak) = try Self.peak(of: prepared.url)
        #expect(peak <= 1)
        // The loudest channel's own level, neither doubled nor halved.
        #expect(abs(peak - 0.6) < 0.05)
    }

    @Test("A mono file is handed straight through")
    func monoIsUntouched() async throws {
        let source = try Self.write([Self.tone(amplitude: 0.5, seconds: 0...1, of: 1)])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source)
        defer { prepared.cleanUp() }

        #expect(prepared.url == source)
        #expect(prepared.temporaryFiles.isEmpty)
    }

    // MARK: - Sides

    @Test("A recording's two sources are kept as files of their own")
    func recordingKeepsItsSidesApart() async throws {
        // Each side speaks in its own half of the recording.
        let source = try Self.write([
            Self.tone(amplitude: 0.5, seconds: 0...1, of: 4),
            Self.tone(amplitude: 0.5, seconds: 2...3, of: 4)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source, separatingSources: true)
        defer { prepared.cleanUp() }

        #expect(prepared.sides.map(\.side) == [.microphone, .systemAudio])

        // Each file holds its own channel and not the other one.
        for side in prepared.sides {
            let envelope = try SideEnvelope.measure(side.url, side: side.side)
            let (mine, theirs): (TimeInterval, TimeInterval) = side.side == .microphone
                ? (0.5, 2.5)
                : (2.5, 0.5)
            #expect(envelope.energy(from: mine, to: mine + 0.2) > 0.01)
            #expect(envelope.energy(from: theirs, to: theirs + 0.2) == 0)
        }
    }

    @Test("An imported file is folded whatever its channels say")
    func importedFilesHaveNoSides() async throws {
        // The same two-channel file, arriving as a file rather than as a
        // recording: nothing here knows those channels are two sources, and
        // guessing would file one speaker's words under two speakers.
        let source = try Self.write([
            Self.tone(amplitude: 0.5, seconds: 0...1, of: 4),
            Self.tone(amplitude: 0.5, seconds: 2...3, of: 4)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source)
        defer { prepared.cleanUp() }

        #expect(prepared.sides.isEmpty)
        // Folded, though: both halves are still audible.
        let (_, peak) = try Self.peak(of: prepared.url)
        #expect(peak > 0.4)
    }

    @Test("A side with nothing on it is not a side")
    func silentSideIsDropped() async throws {
        // What the recorder writes when there was nothing playing.
        let source = try Self.write([
            Self.tone(amplitude: 0.5, seconds: 0...1, of: 2),
            [Float](repeating: 0, count: 48_000 * 2)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(source, separatingSources: true)
        defer { prepared.cleanUp() }

        // One side, so one diarization pass — and its words are still known to
        // have come from the room.
        #expect(prepared.sides.map(\.side) == [.microphone])
    }

    @Test("Sides are cut to the same window as the transcript")
    func sidesFollowTheTrim() async throws {
        let source = try Self.write([
            Self.tone(amplitude: 0.5, seconds: 0...3, of: 6),
            Self.tone(amplitude: 0.5, seconds: 1...5, of: 6)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await AudioSourcePreparer.prepare(
            source,
            trimmedTo: KeptRange(start: 2, end: 4),
            separatingSources: true
        )
        defer { prepared.cleanUp() }

        #expect(prepared.sides.count == 2)
        for side in prepared.sides {
            let file = try AVAudioFile(forReading: side.url)
            let seconds = Double(file.length) / file.processingFormat.sampleRate
            #expect(abs(seconds - 2) < 0.05)
        }
        // The microphone stops a second into the window; the call runs on.
        let microphone = try #require(prepared.sides.first { $0.side == .microphone })
        let envelope = try SideEnvelope.measure(microphone.url, side: .microphone)
        #expect(envelope.energy(from: 0.2, to: 0.8) > 0.01)
        #expect(envelope.energy(from: 1.2, to: 1.8) == 0)
    }

    @Test("A trimmed recording is folded too, and leaves one temporary behind")
    func trimIsFoldedAndCleansUpAfterItself() async throws {
        // The kept window holds nothing but the second channel.
        let source = try Self.write([
            Self.tone(amplitude: 0.5, seconds: 0...1, of: 4),
            Self.tone(amplitude: 0.5, seconds: 2...3, of: 4)
        ])
        defer { try? FileManager.default.removeItem(at: source) }

        let before = Self.temporaryFileCount()
        let prepared = try await AudioSourcePreparer.prepare(
            source,
            trimmedTo: KeptRange(start: 2, end: 4)
        )

        let (channels, peak) = try Self.peak(of: prepared.url)
        #expect(channels == 1)
        #expect(peak > 0.4)
        #expect(prepared.startOffset == 2)
        #expect(abs(prepared.duration - 2) < 0.1)

        // The extraction the trim went through is not left on disk beside the
        // file it was folded into.
        let temporary = try #require(prepared.temporaryFiles.first)
        #expect(prepared.url == temporary)
        #expect(Self.temporaryFileCount() - before == 1)

        prepared.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }
}
