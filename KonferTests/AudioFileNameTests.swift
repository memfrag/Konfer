//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Testing
import Foundation
@testable import Konfer

/// `AVAudioFile` trusts a file's extension, so AAC saved as `.mp3` — which is
/// what turned up in the wild — could neither be drawn nor transcribed. These
/// write real files in one format, rename them to another, and check they
/// come out readable. Synthesised tones, no models, no network.
struct AudioFileNameTests {

    // MARK: - Fixtures

    /// Two seconds of tone in the format the extension names, then renamed to
    /// `.mp3` — the name the format would have if it lied about itself.
    private static func misnamed(_ pathExtension: String, settings: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonferTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let honest = directory.appendingPathComponent("Recording").appendingPathExtension(pathExtension)
        var file: AVAudioFile? = try AVAudioFile(forWriting: honest, settings: settings)

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let frames = AVAudioFrameCount(44_100 * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            buffer.floatChannelData![0][frame] = 0.5 * Float(sin(2 * .pi * 440 * Double(frame) / 44_100))
        }
        try file?.write(from: buffer)
        // Only a closed file is a valid one.
        file = nil

        let lying = directory.appendingPathComponent("Recording.mp3")
        try FileManager.default.moveItem(at: honest, to: lying)
        return lying
    }

    private static func adts() throws -> URL {
        try misnamed("aac", settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
        ])
    }

    private static func wav() throws -> URL {
        try misnamed("wav", settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ])
    }

    private static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Tests

    @Test("AAC named .mp3 is read through a link named .aac")
    func adtsNamedMP3() throws {
        let source = try Self.adts()
        defer { Self.remove(source) }
        #expect((try? AVAudioFile(forReading: source)) == nil)

        let readable = AudioFileName.readable(source)

        #expect(readable.pathExtension == "aac")
        #expect(readable.deletingPathExtension().lastPathComponent == "Recording")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: readable.path)
            == source.standardizedFileURL.path)
        #expect((try? AVAudioFile(forReading: readable)) != nil)
    }

    @Test("A WAV named .mp3 is read through a link named .wav")
    func wavNamedMP3() throws {
        let source = try Self.wav()
        defer { Self.remove(source) }

        let readable = AudioFileName.readable(source)

        #expect(readable.pathExtension == "wav")
        #expect((try? AVAudioFile(forReading: readable)) != nil)
    }

    @Test("Asking twice for the same file gives the same link")
    func linkIsReused() throws {
        let source = try Self.adts()
        defer { Self.remove(source) }

        #expect(AudioFileName.readable(source) == AudioFileName.readable(source))
    }

    @Test("A correctly named file is returned as it is")
    func correctNameIsKept() throws {
        let source = try Self.adts()
        defer { Self.remove(source) }
        let honest = source.deletingPathExtension().appendingPathExtension("aac")
        try FileManager.default.moveItem(at: source, to: honest)

        #expect(AudioFileName.readable(honest) == honest)
    }

    @Test("A file nothing recognises is returned as it is")
    func noiseIsKept() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonferTest-\(UUID().uuidString)")
            .appendingPathExtension("mp3")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(AudioFileName.readable(url) == url)
    }

    @Test("A missing file is returned as it is")
    func missingIsKept() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mp3")
        #expect(AudioFileName.readable(url) == url)
    }

    @Test("AAC named .mp3 has a waveform")
    func misnamedHasWaveform() async throws {
        let source = try Self.adts()
        defer { Self.remove(source) }

        let waveform = await WaveformStore.waveform(at: source)

        #expect(waveform?.isEmpty == false)
    }

    @Test("AAC named .mp3 is prepared for the pipeline as audio it can open")
    func misnamedIsPrepared() async throws {
        let source = try Self.adts()
        defer { Self.remove(source) }

        let prepared = try await AudioSourcePreparer.prepare(source)
        defer { prepared.cleanUp() }

        #expect(abs(prepared.sourceDuration - 2) < 0.1)
        #expect((try? AVAudioFile(forReading: prepared.url)) != nil)
        // The link is shared with the player and the waveform, so a run's
        // clean-up must not take it with it.
        #expect(!prepared.temporaryFiles.contains(prepared.url))
    }

    @Test("A trimmed AAC named .mp3 is cut without a detour through an export")
    func misnamedTrimIsDerived() async throws {
        let source = try Self.adts()
        defer { Self.remove(source) }

        let prepared = try await AudioSourcePreparer.prepare(
            source,
            trimmedTo: KeptRange(start: 0.5, end: 1.5)
        )
        defer { prepared.cleanUp() }

        #expect(abs(prepared.duration - 1) < 0.05)
        let file = try AVAudioFile(forReading: prepared.url)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 1) < 0.05)
    }
}
