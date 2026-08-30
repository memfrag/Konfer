//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation
import WhisperKit

/// Speech recognition via KB-Whisper, the National Library of Sweden's Whisper
/// fine-tune, running on CoreML through WhisperKit.
///
/// Chosen for Swedish: on real meeting audio it recovers whole phrases Parakeet
/// turns to noise — "Resans roll i att öka omsättningen" where Parakeet gives
/// "Reslånser om i ökonsättning". It also returns word timings, so speaker
/// alignment and word-level playback highlighting work exactly as before.
///
/// The first load of a variant compiles the CoreML models, which takes minutes
/// for `large`; every load after that is about a second.
///
/// Counts decoded tokens, as a fine-grained progress signal.
///
/// WhisperKit's own `Progress` only advances when a whole slice finishes — four
/// updates for a five-minute recording, and on an hour that is minutes of a
/// motionless bar. Its decoder callback fires per token instead: 1519 times for
/// the same five minutes.
private nonisolated final class TokenCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    /// Roughly how far through the audio the decoder is.
    ///
    /// Deliberately pessimistic. Measured at about 4.8 tokens per second of
    /// Swedish meeting audio; assuming 5.5 keeps the estimate just behind the
    /// truth, so it lags rather than stalling at 99%, and the exact
    /// slice-completion figure pulls it up whenever a slice lands.
    func estimatedFraction(forAudioSeconds seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return min(Double(count) / (seconds * 5.5), 0.95)
    }
}

actor WhisperKitBackend: TranscriptionBackend {

    private let variant: KBWhisperModelStore.Variant
    private var whisperKit: WhisperKit?

    init(variant: KBWhisperModelStore.Variant) {
        self.variant = variant
    }

    /// Whisper's language code for a meeting's declared language.
    ///
    /// `.auto` maps to Swedish rather than to nil: per-chunk detection is
    /// actively harmful on this material, and Whisper still handles English
    /// stretches inside a Swedish-pinned file perfectly well.
    private nonisolated static func whisperLanguage(for language: MeetingLanguage) -> String? {
        switch language {
        case .auto, .swedish: "sv"
        case .english: "en"
        }
    }

    /// How WhisperKit splits the file before transcribing.
    ///
    /// `.none`, deliberately, even though `.vad` is WhisperKit's own default
    /// and more than twice as fast. Measured on five minutes of a real Swedish
    /// meeting, words recovered and share of the recording covered:
    ///
    /// | Strategy                    | Words     | Covered | Time |
    /// |-----------------------------|-----------|---------|------|
    /// | `.vad`, WhisperKit's EnergyVAD | 606    |     66% |  33s |
    /// | `.vad`, ``DiarizationVAD``  | 483–791   |  51–86% |  42s |
    /// | `.none`                     | 813, 813  |     86% |  93s |
    ///
    /// The ranges are not a typo. **Chunked transcription is not
    /// deterministic**: the same file, the same settings and the same speech
    /// regions produced 791, 657 and 639 words on three consecutive runs.
    /// Unchunked produced 813 twice, identically. A chunk that fails to decode
    /// is dropped with nothing but a debug log
    /// (`AudioChunker.updateSeekOffsetsForResults`), so with 16 concurrent
    /// workers a transient failure silently removes part of the meeting — and
    /// looks exactly like a pause.
    ///
    /// ``DiarizationVAD`` fixes the *detector* — it beats energy thresholding
    /// comfortably — but it cannot fix that. A meeting transcript that differs
    /// each time you produce it is not worth halving the wait for, so chunking
    /// stays off unless the user opts in via Settings ▸ Transcription.
    /// `SNOOPY_CHUNKING` overrides both, for comparison runs.
    nonisolated static func chunkingStrategy(allowed: Bool) -> ChunkingStrategy {
        if let override = ProcessInfo.processInfo.environment["SNOOPY_CHUNKING"]
            .flatMap(ChunkingStrategy.init(rawValue:)) {
            return override
        }
        return allowed ? .vad : .none
    }

    /// The VAD used when chunking is on.
    ///
    /// WhisperKit's default `EnergyVAD` uses a 0.02 energy threshold and *no*
    /// frame overlap, and its own documentation says overlap is what "catches
    /// audio that starts exactly at chunk boundaries". On far-field meeting
    /// audio the default clips quiet speech at the seams.
    nonisolated static var voiceActivityDetector: VoiceActivityDetector? {
        let environment = ProcessInfo.processInfo.environment
        guard let threshold = environment["SNOOPY_VAD_THRESHOLD"].flatMap(Float.init)
        else { return nil }
        let overlap = environment["SNOOPY_VAD_OVERLAP"].flatMap(Float.init) ?? 0
        return EnergyVAD(frameLength: 0.1, frameOverlap: overlap, energyThreshold: threshold)
    }

    /// How many long slices to cut a recording into, for a given duration.
    ///
    /// Roughly one slice per 75 seconds, capped at 8 — beyond that the seams
    /// stop paying for themselves and the Neural Engine is the bottleneck
    /// anyway. Measured on five minutes: one slice 93s, two 54s, four 42s, with
    /// word counts of 813, 811 and 832 — no loss, and repeatable to the word.
    /// `SNOOPY_SLICES` overrides it; 1 restores a single pass.
    /// How many slices may decode at the same time.
    ///
    /// The Neural Engine is a single shared resource; asking it for eight
    /// concurrent long decodes makes CoreML time out rather than queue.
    nonisolated static let maximumConcurrentSlices = 4

    nonisolated static func sliceCount(for duration: TimeInterval) -> Int {
        if let override = ProcessInfo.processInfo.environment["SNOOPY_SLICES"]
            .flatMap(Int.init) {
            return override
        }
        return min(8, max(1, Int(duration / 75)))
    }

    /// `SNOOPY_WHISPER_VERBOSE=1` turns on WhisperKit's own logging, which is
    /// the only way to see where a slow first load is actually spending time.
    nonisolated static var verboseLogging: Bool {
        ProcessInfo.processInfo.environment["SNOOPY_WHISPER_VERBOSE"] == "1"
    }

    var isPrepared: Bool { whisperKit != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard whisperKit == nil else { return }

        do {
            try await KBWhisperModelStore.download(variant, progress: progress)
        } catch let error as PipelineError {
            throw error
        } catch {
            throw PipelineError.modelDownloadFailed(underlying: error)
        }

        // `tokenizerFolder` falls back to `downloadBase`, so give WhisperKit a
        // concrete place to cache the tokenizer rather than leaving it nil.
        let config = WhisperKitConfig(
            modelFolder: KBWhisperModelStore.directory(for: variant).path,
            tokenizerFolder: KBWhisperModelStore.directory,
            voiceActivityDetector: Self.voiceActivityDetector,
            verbose: Self.verboseLogging,
            logLevel: Self.verboseLogging ? .debug : .error,
            prewarm: false,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
    }

    func unload() {
        whisperKit = nil
    }

    func transcribe(
        _ request: TranscriptionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio {

        guard let whisperKit else { throw PipelineError.modelsNotLoaded }

        // If the user has opted into chunking, at least chunk on the diarizer's
        // segmentation rather than on an energy threshold.
        let strategy = Self.chunkingStrategy(allowed: request.allowsChunking)
        whisperKit.voiceActivityDetector = request.speechRegions.isEmpty
            ? nil
            : DiarizationVAD(regions: request.speechRegions)

        // Pinning the language matters more than it looks. Left to detect,
        // Whisper decides per VAD chunk, and a Swedish meeting sprinkled with
        // "stakeholder" and "AI" makes chunks flip language — which produces
        // text merged from the wrong parts of the recording. Auto stays
        // available, but Swedish is the default because that is what these
        // recordings are.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: Self.whisperLanguage(for: request.language),
            wordTimestamps: true,
            chunkingStrategy: strategy
        )

        // Nothing is reported until a transcribe call returns, which left the
        // bar frozen for the whole run. Two signals fix that: slices completing
        // (exact, but rare) and tokens decoding (an estimate, but constant).
        let tokens = TokenCounter()
        completedFraction = 0
        let audioSeconds = (try? await AVURLAsset(url: request.url).load(.duration).seconds) ?? 0

        let reporter = Task { [weak self] in
            var reported = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let completed = await self?.completedFraction else { return }
                let fraction = max(completed, tokens.estimatedFraction(forAudioSeconds: audioSeconds))
                // Monotonic and short of 1: finishing is the caller's to report,
                // and a bar that goes backwards looks broken.
                if fraction > reported {
                    reported = fraction
                    progress(min(fraction, 0.99))
                }
            }
        }
        defer { reporter.cancel() }

        let results: [TranscriptionResult]
        var sliceCuts: [TimeInterval] = []
        if strategy == ChunkingStrategy.none, !request.speechRegions.isEmpty {
            (results, sliceCuts) = try await transcribeInSlices(
                request, options: options, using: whisperKit, tokens: tokens
            )
        } else {
            results = try await whisperKit.transcribe(
                audioPath: request.url.path,
                decodeOptions: options,
                callback: { _ in
                    tokens.increment()
                    return nil
                }
            )
        }

        progress(1)

        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let words = results
            .flatMap(\.allWords)
            .map {
                WordSpan(
                    word: $0.word.trimmingCharacters(in: .whitespaces),
                    start: TimeInterval($0.start),
                    end: TimeInterval($0.end)
                )
            }
            .filter { !$0.word.isEmpty }

        // Word timings are what the aligner attributes to speakers, so a result
        // with text but no timings would silently produce one giant turn.
        guard !words.isEmpty else {
            return TranscribedAudio(
                text: text,
                words: text.isEmpty
                    ? []
                    : [WordSpan(word: text, start: 0, end: 0)],
                sliceCuts: sliceCuts
            )
        }

        return TranscribedAudio(text: text, words: words, sliceCuts: sliceCuts)
    }

    /// The share of slices actually finished, 0...1.
    ///
    /// Counted here rather than read from `WhisperKit.progress`, which is
    /// over-subscribed: it adds a child per slice but never raises its own
    /// total, so it reaches 1.0 after the first batch and stays there. That put
    /// the bar at 99% for 31 of a 52-second stage.
    private var completedFraction = 0.0

    // MARK: - Coarse slicing

    /// Transcribes the file as a handful of long slices, in parallel.
    ///
    /// WhisperKit's own chunker caps every chunk at its 30-second window, so it
    /// cannot be asked for "four chunks" — five minutes is at least ten chunks
    /// and an hour over a hundred, each seam somewhere speech can be lost. This
    /// works one level up: cut the recording into a few long slices at real
    /// silences, transcribe each in one complete unchunked pass, and let
    /// WhisperKit run the slices concurrently.
    ///
    /// The failure mode that makes chunking unreliable is handled here too. A
    /// slice that fails comes back as a `Result` we inspect and surface, rather
    /// than disappearing into a debug log.
    private func transcribeInSlices(
        _ request: TranscriptionRequest,
        options: DecodingOptions,
        using whisperKit: WhisperKit,
        tokens: TokenCounter
    ) async throws -> (results: [TranscriptionResult], cuts: [TimeInterval]) {

        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: request.url.path)
        let sampleRate = Double(WhisperKit.sampleRate)
        let duration = Double(samples.count) / sampleRate

        // Diarization gaps give the rough positions; the audio decides the
        // exact ones. A cut in the middle of a word is the only thing that
        // makes slicing cost anything.
        let candidates = SpeechRegion.cutPoints(
            in: request.speechRegions,
            duration: duration,
            slices: Self.sliceCount(for: duration)
        )
        let cuts = SpeechRegion.quietest(
            near: candidates,
            in: samples,
            sampleRate: sampleRate
        )
        if Self.verboseLogging {
            print("SLICING: \(request.speechRegions.count) regions -> "
                  + "\(cuts.count) cuts at \(cuts.map { Int($0) })")
        }
        guard !cuts.isEmpty else {
            // No safe place to cut: one pass is the correct answer.
            let whole = try await whisperKit.transcribe(
                audioPath: request.url.path,
                decodeOptions: options,
                callback: { _ in
                    tokens.increment()
                    return nil
                }
            )
            return (whole, [])
        }

        let bounds = [0] + cuts.map { Int($0 * sampleRate) } + [samples.count]
        let slices = zip(bounds, bounds.dropFirst()).map { Array(samples[$0..<$1]) }

        // Cap how many slices decode at once. There is one Neural Engine, and
        // eight simultaneous ten-minute decodes overrun it: CoreML gives up
        // with "ANE op async execution has timed out". Four is what the
        // hardware sustains.
        var sliceOptions = options
        sliceOptions.concurrentWorkerCount = Self.maximumConcurrentSlices

        // Submitted a batch at a time rather than all at once, so each batch
        // returning is an honest progress milestone. WhisperKit would batch
        // these itself, but then nothing is observable until every slice is
        // done.
        var outcomes: [Result<[TranscriptionResult], Swift.Error>] = []
        for start in stride(from: 0, to: slices.count, by: Self.maximumConcurrentSlices) {
            let batch = Array(slices[start..<min(start + Self.maximumConcurrentSlices, slices.count)])
            outcomes += await whisperKit.transcribeWithOptions(
                audioArrays: batch,
                decodeOptionsArray: Array(repeating: sliceOptions, count: batch.count),
                callback: { _ in
                    tokens.increment()
                    return nil
                }
            )
            completedFraction = Double(outcomes.count) / Double(slices.count)
        }

        var results: [TranscriptionResult] = []
        for (index, outcome) in outcomes.enumerated() {
            switch outcome {
            case .success(let sliceResults):
                // Slice timings are relative to the slice; make them absolute.
                let offset = Float(bounds[index]) / Float(WhisperKit.sampleRate)
                results += sliceResults.map { result in
                    result.segments = result.segments.map {
                        TranscriptionUtilities.updateSegmentTimings(segment: $0, seekTime: offset)
                    }
                    return result
                }
            case .failure(let error):
                throw PipelineError.transcriptionFailed(underlying: error)
            }
        }
        return (results, cuts)
    }
}
