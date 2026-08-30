//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

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

        let results = try await whisperKit.transcribe(
            audioPath: request.url.path,
            decodeOptions: options
        )

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
                    : [WordSpan(word: text, start: 0, end: 0)]
            )
        }

        return TranscribedAudio(text: text, words: words)
    }
}
