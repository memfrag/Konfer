//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation
import Speech

/// Speech recognition via Apple's on-device `SpeechTranscriber` (macOS 26).
///
/// Used for English, where it is fast, free of any download we have to manage,
/// and already installed on most Macs. It cannot be used for Swedish:
/// `SpeechTranscriber.supportedLocales` covers 30 locales — German, English,
/// Spanish, French, Italian, Japanese, Korean, Portuguese and Chinese variants
/// — and Swedish is not among them. That gap is precisely why KB-Whisper is
/// still here.
///
actor AppleSpeechBackend: TranscriptionBackend {

    /// Languages Apple's transcriber can actually handle, as far as Snoopy is
    /// concerned.
    static func supports(_ language: MeetingLanguage) -> Bool {
        language == .english
    }

    private var isReady = false

    var isPrepared: Bool { isReady }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isReady else { return }

        guard SpeechTranscriber.isAvailable else {
            throw PipelineError.appleSpeechUnavailable
        }

        let locale = try await Self.resolvedLocale()
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        // The locale's model may not be installed yet. Unlike the other
        // backends this is Apple's own asset pipeline, so there is nothing for
        // Snoopy to cache or clean up afterwards.
        if let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await request.downloadAndInstall()
        }

        progress(1)
        isReady = true
    }

    func unload() {
        isReady = false
    }

    /// - Parameter speechRegions: Ignored. `SpeechAnalyzer` consumes the file
    ///   itself and does its own segmentation.
    func transcribe(
        _ url: URL,
        language: MeetingLanguage,
        speechRegions: [SpeechRegion],
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio {

        guard Self.supports(language) else {
            throw PipelineError.languageUnsupported(language)
        }

        let locale = try await Self.resolvedLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            // Word timings are the whole point: they are what the aligner
            // attributes to speakers.
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        // Collect results while the analyzer consumes the file.
        let collector = Task { () -> [WordSpan] in
            var words: [WordSpan] = []
            for try await result in transcriber.results {
                words.append(contentsOf: Self.wordSpans(in: result.text))
            }
            return words
        }

        _ = try await analyzer.analyzeSequence(from: file)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let words = try await collector.value
        progress(1)

        return TranscribedAudio(
            text: SpeakerAligner.joined(words),
            words: words
        )
    }

    // MARK: - Results

    /// Pulls one span per attributed run that carries an audio time range.
    ///
    /// `SpeechTranscriber` returns an `AttributedString` whose runs are tagged
    /// with `.audioTimeRange` when that attribute is requested; those runs are
    /// the words.
    private nonisolated static func wordSpans(in text: AttributedString) -> [WordSpan] {
        var spans: [WordSpan] = []

        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let word = String(text[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }

            spans.append(
                WordSpan(
                    word: word,
                    start: range.start.seconds,
                    end: range.end.seconds
                )
            )
        }
        return spans
    }

    // MARK: - Locale

    /// The installed English locale closest to the user's own region.
    private static func resolvedLocale() async throws -> Locale {
        let preferred = Locale.current
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: preferred),
           match.language.languageCode?.identifier == "en" {
            return match
        }
        if let english = await SpeechTranscriber.supportedLocales.first(where: {
            $0.identifier(.bcp47) == "en-US"
        }) {
            return english
        }
        throw PipelineError.appleSpeechUnavailable
    }
}
