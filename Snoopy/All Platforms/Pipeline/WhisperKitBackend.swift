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
        _ url: URL,
        language: MeetingLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio {

        guard let whisperKit else { throw PipelineError.modelsNotLoaded }

        // Pinning the language matters more than it looks. Left to detect,
        // Whisper decides per VAD chunk, and a Swedish meeting sprinkled with
        // "stakeholder" and "AI" makes chunks flip language — which produces
        // text merged from the wrong parts of the recording. Auto stays
        // available, but Swedish is the default because that is what these
        // recordings are.
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: Self.whisperLanguage(for: language),
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        let results = try await whisperKit.transcribe(
            audioPath: url.path,
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
