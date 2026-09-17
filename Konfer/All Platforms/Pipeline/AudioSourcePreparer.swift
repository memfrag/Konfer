//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Accelerate
import Foundation

/// The audio file handed to FluidAudio, plus how to clean up after it.
nonisolated struct PreparedAudio: Sendable {

    /// The file the pipeline should read. Either the user's own file or a
    /// temporary one derived from it: audio extracted from video, a trim, or
    /// the channels folded into one.
    let url: URL

    /// Length of `url` — the trimmed extract when there is one, so the stages
    /// reading it report progress against what they actually process.
    let duration: TimeInterval

    /// Length of the file the user chose, which is what the meeting records:
    /// the library points at their recording, whole, however little of it was
    /// transcribed.
    let sourceDuration: TimeInterval

    /// Where the prepared audio begins within the source, so the pipeline can
    /// put the timestamps back where they belong. Zero unless trimmed.
    let startOffset: TimeInterval

    /// The recording's sources as separate mono files, on the same timeline
    /// as `url`. Empty unless the caller said this recording keeps its sources
    /// apart; one entry when only one of them turned out to carry signal.
    let sides: [PreparedSide]

    /// Temporary files this run created, for it to delete afterwards.
    let temporaryFiles: [URL]

    /// How much of the call the microphone turned out to be hearing, when
    /// suppression was asked for and found something to act on. Nil when it
    /// was not asked for, or when the two sides were not tracking each other.
    var bleed: BleedSuppression.Coupling?

    func cleanUp() {
        for file in temporaryFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// One source of a two-sided recording, on its own.
nonisolated struct PreparedSide: Sendable {
    let side: RecordingSide
    let url: URL
}

/// Normalizes whatever the user dropped into something FluidAudio can open:
/// one channel, no video container.
///
/// Both `AudioConverter.resampleAudioFile` and `AudioSourceFactory` open files
/// with `AVAudioFile`, which reads audio containers but not video ones. Since
/// video input is in scope, a video file has its audio track exported to a
/// temporary `.m4a` first; everything downstream then sees a plain audio file
/// and knows nothing about video.
///
nonisolated enum AudioSourcePreparer {

    /// - Parameters:
    ///   - trimmedTo: The stretch to transcribe, or nil for all of it. The
    ///     stages downstream take a file and have nowhere to put a range, so a
    ///     trim is always a new file.
    ///   - separatingSources: Whether this recording keeps two independent
    ///     sources on its two channels — the microphone and system audio, as
    ///     ``TwoChannelWriter`` writes them. Only the recorder knows that, and
    ///     it is not a thing to guess at: an ordinary stereo file is one sound
    ///     field in two channels, and a pair of microphones a metre apart
    ///     correlates no better than two unrelated sources do. Claimed
    ///     wrongly, it would file one speaker's words under two speakers.
    ///   - suppressingBleed: Whether to silence the microphone side wherever it
    ///     is only hearing the call — see ``BleedSuppression``. The user's
    ///     choice, not ours: it is measurable but not certain, and a recording
    ///     where it guesses wrong is one where a quiet voice in the room was
    ///     gated out of the *diarization* input. Only ever applied to the side
    ///     files; the fold speech recognition reads is untouched either way.
    static func prepare(
        _ url: URL,
        trimmedTo trim: KeptRange? = nil,
        separatingSources: Bool = false,
        suppressingBleed: Bool = false
    ) async throws -> PreparedAudio {

        let asset = AVURLAsset(url: url)

        let sourceDuration: TimeInterval
        do {
            sourceDuration = try await asset.load(.duration).seconds
        } catch {
            throw PipelineError.audioUnreadable(url, underlying: error)
        }

        // Clamped to the file: a range dragged to the very end can name a
        // moment a fraction past the last sample, and an export session given
        // one fails rather than shrugging.
        let range = trim.map {
            KeptRange(
                start: max(0, min($0.start, sourceDuration)),
                end: max(0, min($0.end, sourceDuration))
            )
        }

        let hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty

        var working = url
        var temporary: URL?
        var pendingRange = range

        // Video, or audio in a container `AVAudioFile` cannot open, has to go
        // through an export session; anything else is trimmed in the pass that
        // folds it, which is both exact to the sample and free of the AAC
        // round trip an export would put in the way of two unrelated sources.
        if hasVideo || (range != nil && (try? AVAudioFile(forReading: url)) == nil) {
            guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
                throw PipelineError.noAudioTrack(url)
            }
            working = try await extractAudio(from: asset, trimmedTo: range)
            temporary = working
            pendingRange = nil
        }

        var sides: [PreparedSide] = []

        if let derived = try derive(
            working,
            keeping: pendingRange,
            separatingSources: separatingSources && !hasVideo,
            suppressingBleed: suppressingBleed
        ) {
            // Whatever it was derived from was only ever a step on the way.
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
            working = derived.mono
            temporary = derived.mono
            sides = derived.sides
        }

        // After the sides exist and before anything reads them: diarization is
        // the stage this protects, and it is the next one.
        let bleed = suppressingBleed ? suppressBleed(between: sides) : nil

        return PreparedAudio(
            url: working,
            duration: range.map(\.duration) ?? sourceDuration,
            sourceDuration: sourceDuration,
            startOffset: range?.start ?? 0,
            sides: sides,
            temporaryFiles: [temporary].compactMap { $0 } + sides.map(\.url),
            bleed: bleed
        )
    }

    // MARK: - Bleed

    /// `KONFER_BLEED_DIAGNOSTICS=1` reports what the coupling was measured as
    /// and how much of the microphone it silenced, which is the only way to
    /// tell "found no bleed" apart from "found it and left it alone".
    nonisolated static var isDiagnostic: Bool {
        ProcessInfo.processInfo.environment["KONFER_BLEED_DIAGNOSTICS"] == "1"
    }

    /// Silences the microphone side wherever it is only hearing the call.
    ///
    /// Works on the side files rather than during the fold, which costs one
    /// more read of one mono channel and buys the loudness measurement that
    /// ``SideEnvelope`` already knows how to make. The fold is not touched: see
    /// ``BleedSuppression``.
    ///
    /// - Returns: What it measured and acted on, or nil when the two sides were
    ///   not tracking each other closely enough to call it bleed.
    private static func suppressBleed(between sides: [PreparedSide]) -> BleedSuppression.Coupling? {
        guard let microphone = sides.first(where: { $0.side == .microphone }),
              let system = sides.first(where: { $0.side == .systemAudio }),
              let microphoneEnvelope = try? SideEnvelope.measure(microphone.url, side: .microphone),
              let systemEnvelope = try? SideEnvelope.measure(system.url, side: .systemAudio),
              let coupling = BleedSuppression.coupling(
                  microphone: microphoneEnvelope.frames,
                  system: systemEnvelope.frames
              )
        else { return nil }

        let gate = BleedSuppression.gate(
            microphone: microphoneEnvelope.frames,
            system: systemEnvelope.frames,
            coupling: coupling
        )
        if isDiagnostic {
            let silenced = gate.filter { $0 }.count
            print(String(
                format: "BLEED: %.0f%% of frames explained at %d frames (%.0f ms), %.1f dB down, "
                    + "silencing %d of %d frames",
                coupling.evidence * 100,
                coupling.lag,
                Double(coupling.lag) * SideEnvelope.frameDuration * 1000,
                coupling.decibels,
                silenced,
                gate.count
            ))
        }
        guard gate.contains(true) else { return coupling }
        do {
            try silence(gate, in: microphone.url)
        } catch {
            // The recording is still perfectly transcribable with the bleed in
            // it — one invented speaker in the roster is not worth failing a
            // run over, and the roster drops unheard clusters anyway.
            return nil
        }
        return coupling
    }

    /// Rewrites a mono side file with the gated frames zeroed.
    private static func silence(_ gate: [Bool], in url: URL) throws {
        let input = try AVAudioFile(forReading: url)
        let rate = input.processingFormat.sampleRate
        let perFrame = max(1, Int(rate * SideEnvelope.frameDuration))
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: 1,
            interleaved: false
        ) else { return }

        let scratch = temporaryURL()
        var output: AVAudioFile? = try monoFile(at: scratch, rate: rate)

        var position = 0
        try AudioBuffers.forEach(in: input) { buffer in
            guard let data = buffer.floatChannelData else { return }
            let count = Int(buffer.frameLength)
            try write(buffer.frameLength, format: format, to: output) { target in
                target.update(from: data[0], count: count)
                for offset in 0..<count {
                    let frame = (position + offset) / perFrame
                    if frame < gate.count, gate[frame] { target[offset] = 0 }
                }
            }
            position += count
        }
        // Released before the file is moved: an `.m4a` is only valid once
        // `AVAudioFile` has finalised its container, which it does on release.
        output = nil

        _ = try FileManager.default.replaceItemAt(url, withItemAt: scratch)
    }

    // MARK: - Channels

    /// What one read pass produced: the single channel every stage reads, and
    /// the recording's two sources kept apart when it has two.
    private struct Derived {
        let mono: URL
        let sides: [PreparedSide]
    }

    /// Below this a channel is a dead input or digital silence rather than a
    /// source — a peak of 0.005 is −46 dBFS, and a microphone left muted for
    /// an hour does not reach it.
    private static let silenceFloor: Float = 0.005

    /// Folds every channel of a file into one, applies any trim, and writes
    /// the two sides separately when this recording has two. Nil when the file
    /// is already a single channel and nothing is being cut out of it.
    ///
    /// The fold is the step that makes the second source audible at all. A
    /// Konfer recording keeps the microphone on channel 0 and system audio on
    /// channel 1 — see ``TwoChannelWriter`` — and every stage downstream
    /// reduces the file to 16 kHz mono before it looks at it. FluidAudio does
    /// that with an `AVAudioConverter`, and so, evidently, does
    /// `SpeechAnalyzer`: asked for one channel out of two, that converter
    /// **keeps channel 0 and discards the rest** rather than mixing them.
    /// Measured on a file with a different sentence on each channel, the
    /// system-audio half comes back as digital silence — peak 0.0 — and
    /// Apple's transcriber returns the microphone sentence alone. WhisperKit
    /// sums channels itself, which is why Swedish heard both sides while
    /// English never did.
    ///
    /// The sum is scaled so its peak matches the loudest single channel rather
    /// than being halved, which both prevents a clip where the two sides talk
    /// over each other and leaves a quiet far-field microphone where it was.
    /// One global factor, not one per buffer: a gain that moves with the
    /// content is a gain the diarizer's embeddings can hear. It costs a second
    /// decode pass — folding an hour of 48 kHz stereo takes 11 s all told,
    /// against the ten minutes that hour spends being transcribed.
    ///
    /// The sides are written during the same pass, so keeping them costs one
    /// more file rather than one more read.
    private static func derive(
        _ url: URL,
        keeping range: KeptRange?,
        separatingSources: Bool,
        suppressingBleed: Bool = false
    ) throws -> Derived? {

        // A file `AVAudioFile` cannot open is left exactly as it is: the stage
        // that needs it reports that far better than a preparation step can.
        guard let input = try? AVAudioFile(forReading: url) else { return nil }
        let format = input.processingFormat
        let channels = Int(format.channelCount)
        guard channels > 1 || range != nil else { return nil }

        let bounds = frames(of: range, at: format.sampleRate, length: input.length)

        do {
            // Pass one: the peaks that set the gain, and whether both sources
            // turned out to have anything on them.
            var loudestSum: Float = 0
            var peaks = [Float](repeating: 0, count: channels)

            try AudioBuffers.forEach(in: input, within: bounds) { buffer in
                let frames = vDSP_Length(buffer.frameLength)
                guard let data = buffer.floatChannelData else { return }
                for channel in 0..<channels {
                    var peak: Float = 0
                    vDSP_maxmgv(data[channel], 1, &peak, frames)
                    peaks[channel] = max(peaks[channel], peak)
                }
                var peak: Float = 0
                vDSP_maxmgv(Self.sum(buffer, channels: channels), 1, &peak, frames)
                loudestSum = max(loudestSum, peak)
            }
            let loudestChannel = peaks.max() ?? 0
            var gain = loudestSum > 0 ? loudestChannel / loudestSum : 1

            // A side with nothing on it is not a side: a meeting recorded
            // with nothing playing has one source, whatever the recorder
            // believed when it started, and diarizing its silent half would
            // cost a pass to find nobody. The other side keeps its name.
            let present: [RecordingSide] = separatingSources && channels == 2
                ? RecordingSide.allCases.filter { peaks[$0.channel] > silenceFloor }
                : []

            // Pass two: write it, and the sides with it.
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: format.sampleRate,
                channels: 1,
                interleaved: false
            ) else { return nil }

            let mono = temporaryURL()
            var output: AVAudioFile? = try monoFile(at: mono, rate: format.sampleRate)

            let sides = present.map { PreparedSide(side: $0, url: temporaryURL()) }
            var sideFiles: [AVAudioFile?] = try sides.map {
                try monoFile(at: $0.url, rate: format.sampleRate)
            }

            try AudioBuffers.forEach(in: input, within: bounds) { buffer in
                guard let data = buffer.floatChannelData else { return }
                let frames = vDSP_Length(buffer.frameLength)

                let summed = Self.sum(buffer, channels: channels)
                try Self.write(buffer.frameLength, format: monoFormat, to: output) { target in
                    vDSP_vsmul(summed, 1, &gain, target, 1, frames)
                }

                for (index, side) in sides.enumerated() {
                    try Self.write(buffer.frameLength, format: monoFormat, to: sideFiles[index]) { target in
                        target.update(from: data[side.side.channel], count: Int(frames))
                    }
                }
            }
            // An `.m4a` is only a valid file once `AVAudioFile` has finalised
            // its container, which it does when it is released — so these have
            // to be let go before anyone reads them, not merely finished with.
            output = nil
            sideFiles = []

            return Derived(mono: mono, sides: sides)
        } catch {
            throw PipelineError.audioUnreadable(url, underlying: error)
        }
    }

    /// A time range as frame positions in a file, clamped to it.
    private static func frames(
        of range: KeptRange?,
        at rate: Double,
        length: AVAudioFramePosition
    ) -> Range<AVAudioFramePosition>? {
        guard let range else { return nil }
        let start = max(0, min(AVAudioFramePosition(range.start * rate), length))
        let end = max(start, min(AVAudioFramePosition(range.end * rate), length))
        return start..<end
    }

    private static func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Konfer-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    /// Lossless, for the same reason the recorder is: these files are what the
    /// whole transcript is derived from.
    private static func monoFile(at url: URL, rate: Double) throws -> AVAudioFile {
        try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 16,
        ])
    }

    private static func write(
        _ frames: AVAudioFrameCount,
        format: AVAudioFormat,
        to file: AVAudioFile?,
        filling: (UnsafeMutablePointer<Float>) -> Void
    ) throws {
        guard let file,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let target = buffer.floatChannelData
        else { return }
        buffer.frameLength = frames
        filling(target[0])
        try file.write(from: buffer)
    }

    /// Every channel of one buffer added together, unscaled.
    private static func sum(_ buffer: AVAudioPCMBuffer, channels: Int) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard let data = buffer.floatChannelData else { return [] }
        var summed = [Float](repeating: 0, count: frames)
        summed.withUnsafeMutableBufferPointer { output in
            for channel in 0..<channels {
                vDSP_vadd(
                    output.baseAddress!, 1,
                    data[channel], 1,
                    output.baseAddress!, 1,
                    vDSP_Length(frames)
                )
            }
        }
        return summed
    }

    // MARK: - Video

    private static func extractAudio(
        from asset: AVURLAsset,
        trimmedTo range: KeptRange?
    ) async throws -> URL {

        let destination = temporaryURL()

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PipelineError.noAudioTrack(asset.url)
        }

        if let range {
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                end: CMTime(seconds: range.end, preferredTimescale: 600)
            )
        }

        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw PipelineError.audioUnreadable(asset.url, underlying: error)
        }

        return destination
    }
}
