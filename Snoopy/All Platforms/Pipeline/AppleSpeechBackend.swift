//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation
import Speech

/// Speech recognition via Apple's on-device `SpeechTranscriber` (macOS 26).
///
/// Fast, and free of any download Snoopy has to manage. It covers 30 locales —
/// German, English, Spanish, French, Italian, Japanese, Korean, Portuguese and
/// Chinese variants — which is why Snoopy offers six languages it has no model
/// for. Run `scripts/supported-locales.swift` to see the current list on a
/// given Mac; Swedish, Danish, Dutch and Polish are not in it, which is
/// precisely why the Whisper backends are still here.
///
/// Unlike the other backends this one is **not bound to a single model**: it
/// resolves a locale per language and asks macOS to install that locale's
/// assets. So readiness is a fact about the locale, not about the backend.
///
actor AppleSpeechBackend: TranscriptionBackend {

    /// Languages Apple's transcriber can actually handle, as far as Snoopy is
    /// concerned. The pipeline checks this before it starts; the guard in
    /// ``transcribe(_:progress:)`` is the backstop.
    static func supports(_ language: MeetingLanguage) -> Bool {
        ASRBackendKind.appleSpeech.supports(language)
    }

    /// The locale currently installed and loaded, or nil. Not a `Bool`, because
    /// being ready for English says nothing about German.
    private var preparedLocale: Locale?

    func isPrepared(for language: MeetingLanguage) async -> Bool {
        guard let preparedLocale,
              let locale = try? await Self.resolvedLocale(for: language) else { return false }
        return preparedLocale == locale
    }

    func prepare(
        for language: MeetingLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {

        guard SpeechTranscriber.isAvailable else {
            throw PipelineError.appleSpeechUnavailable
        }

        let locale = try await Self.resolvedLocale(for: language)
        guard preparedLocale != locale else { return }

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
        preparedLocale = locale
    }

    func unload() {
        preparedLocale = nil
    }

    /// `speechRegions` and `allowsChunking` are ignored: `SpeechAnalyzer`
    /// consumes the file itself and does its own segmentation.
    func transcribe(
        _ request: TranscriptionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio {

        guard Self.supports(request.language) else {
            throw PipelineError.languageUnsupported(request.language)
        }

        let locale = try await Self.resolvedLocale(for: request.language)
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            // Word timings are the whole point: they are what the aligner
            // attributes to speakers.
            attributeOptions: [.audioTimeRange]
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: request.url)

        let duration = try await AVURLAsset(url: request.url).load(.duration).seconds

        // Collect results while the analyzer consumes the file. Each result
        // carries the range it covers, which is exactly the progress figure.
        let collector = Task { () -> [WordSpan] in
            var words: [WordSpan] = []
            for try await result in transcriber.results {
                words.append(contentsOf: Self.wordSpans(in: result.text))
                if duration > 0 {
                    progress(min(result.range.end.seconds / duration, 0.99))
                }
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

    /// A supported locale for this language, in the user's own region if there
    /// is one.
    ///
    /// Apple publishes locales, not languages: German alone is `de-AT`, `de-CH`
    /// and `de-DE`. An Austrian transcribing German should get `de-AT`, so the
    /// user's region wins when it exists; otherwise the language's home region
    /// (`de-DE`), and failing that any variant at all, since a wrong region is
    /// a far smaller error than refusing to transcribe.
    static func resolvedLocale(for language: MeetingLanguage) async throws -> Locale {

        let candidates = await SpeechTranscriber.supportedLocales.filter {
            $0.language.languageCode?.identifier == language.code
        }
        guard !candidates.isEmpty else {
            throw PipelineError.languageUnsupported(language)
        }

        if let region = Locale.current.region?.identifier,
           let match = candidates.first(where: { $0.region?.identifier == region }) {
            return match
        }
        return candidates.first { $0.region?.identifier == language.homeRegion }
            ?? candidates[0]
    }
}
