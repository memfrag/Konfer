//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation

/// A downsampled amplitude envelope of a recording, for drawing.
nonisolated struct Waveform: Codable, Sendable {

    /// Peak amplitude per bucket, 0...1, left to right.
    let peaks: [Float]

    var isEmpty: Bool { peaks.isEmpty }
}

/// Computes and caches waveform envelopes.
///
/// Reading an hour of audio takes a few seconds, which is fine once and
/// irritating every time a meeting is opened — so the envelope is written
/// beside the meeting and reused.
nonisolated enum WaveformStore {

    /// Buckets across the whole recording. Roughly two per horizontal point at
    /// a typical window width, which is enough to look like a waveform without
    /// making the file big.
    static let resolution = 2000

    private static var directory: URL {
        LibraryLocation.directory.appendingPathComponent("Waveforms", isDirectory: true)
    }

    private static func fileURL(for meetingID: UUID) -> URL {
        directory.appendingPathComponent("\(meetingID.uuidString).json")
    }

    /// Returns the cached envelope, computing it from the audio if needed.
    ///
    /// Returns `nil` when the recording can't be read — the audio may have been
    /// moved or deleted, which the rest of the app already tolerates.
    static func waveform(for meetingID: UUID, audio url: URL) async -> Waveform? {
        if let cached = try? Data(contentsOf: fileURL(for: meetingID)),
           let waveform = try? JSONDecoder().decode(Waveform.self, from: cached),
           !waveform.isEmpty {
            return waveform
        }

        guard let waveform = await Task.detached(priority: .utility, operation: {
            try? computeWaveform(at: url)
        }).value else { return nil }

        cache(waveform, for: meetingID)
        return waveform
    }

    private static func cache(_ waveform: Waveform, for meetingID: UUID) {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(waveform) else { return }
        try? data.write(to: fileURL(for: meetingID), options: .atomic)
    }

    // MARK: - Computing

    /// Peak amplitude per bucket, read straight from the file.
    ///
    /// Peak rather than RMS: speech looks like speech at this scale, and quiet
    /// passages stay visible instead of flattening into the baseline — which
    /// matters here, since quiet speech is exactly what the energy VAD missed.
    private static func computeWaveform(at url: URL) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { return Waveform(peaks: []) }

        let framesPerBucket = max(1, Int(totalFrames) / resolution)
        let readSize = AVAudioFrameCount(max(framesPerBucket, 8192))

        var peaks: [Float] = []
        peaks.reserveCapacity(resolution)

        var carry: Float = 0
        var carried = 0

        while file.framePosition < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - file.framePosition)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: min(readSize, remaining)
            ) else { break }

            do {
                try file.read(into: buffer)
            } catch {
                // AVAudioFile.length is an estimate for packetized formats, so a
                // failed read after real audio is the end of the file.
                break
            }
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }

            for frame in 0..<Int(buffer.frameLength) {
                carry = max(carry, abs(channel[frame]))
                carried += 1
                if carried == framesPerBucket {
                    peaks.append(carry)
                    carry = 0
                    carried = 0
                }
            }
        }
        if carried > 0 { peaks.append(carry) }

        // Normalize so a quietly recorded meeting still fills the view.
        let loudest = peaks.max() ?? 0
        guard loudest > 0 else { return Waveform(peaks: peaks) }
        return Waveform(peaks: peaks.map { $0 / loudest })
    }

    static func removeCache(for meetingID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: meetingID))
    }
}
