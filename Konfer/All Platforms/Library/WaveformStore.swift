//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Accelerate
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

        guard let waveform = await Task.detached(priority: .userInitiated, operation: {
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
    ///
    /// Each bucket is one `vDSP_maxmgv` call rather than a Swift loop over its
    /// samples. That is not premature: an hour of audio is over 200 million
    /// samples, and a bounds-checked scalar loop takes 25 seconds in a debug
    /// build against 0.3 in a release one. Accelerate is precompiled, so it is
    /// fast either way — and it is a debug build people run while developing.
    private static func computeWaveform(at url: URL) throws -> Waveform {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0 else { return Waveform(peaks: []) }

        let framesPerBucket = max(1, Int(totalFrames) / resolution)
        // Read a whole number of buckets at a time, so no bucket straddles two
        // reads and no carry has to be tracked between them.
        let bucketsPerRead = max(1, 1_048_576 / framesPerBucket)
        let readSize = AVAudioFrameCount(framesPerBucket * bucketsPerRead)

        var peaks: [Float] = []
        peaks.reserveCapacity(resolution)

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
            let frames = Int(buffer.frameLength)
            guard frames > 0, let channel = buffer.floatChannelData?[0] else { break }

            var offset = 0
            while offset < frames {
                let count = min(framesPerBucket, frames - offset)
                var peak: Float = 0
                vDSP_maxmgv(channel + offset, 1, &peak, vDSP_Length(count))
                peaks.append(peak)
                offset += count
            }
        }

        // Normalize so a quietly recorded meeting still fills the view.
        var loudest: Float = 0
        vDSP_maxv(peaks, 1, &loudest, vDSP_Length(peaks.count))
        guard loudest > 0 else { return Waveform(peaks: peaks) }

        var scale = 1 / loudest
        var scaled = [Float](repeating: 0, count: peaks.count)
        vDSP_vsmul(peaks, 1, &scale, &scaled, 1, vDSP_Length(peaks.count))
        return Waveform(peaks: scaled)
    }

    static func removeCache(for meetingID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: meetingID))
    }
}
