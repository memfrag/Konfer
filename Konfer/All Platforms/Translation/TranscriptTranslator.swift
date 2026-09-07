//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Translation

// MARK: - TranslationAvailability

/// Whether a language pair can be translated on this Mac.
///
/// A narrowing of `Translation.LanguageAvailability.Status` so the import
/// sheet, the queue and the tests can reason about a pair without importing
/// the framework — and, more usefully, without needing its models installed to
/// run.
nonisolated enum TranslationAvailability: Equatable, Sendable {

    /// Ready to translate now.
    case ready

    /// macOS offers this pair but has not downloaded it. Only macOS can fetch
    /// it — see ``TranslationDownloadTask``.
    case needsDownload

    /// macOS offers no translation between these two languages at all.
    ///
    /// Measured across Konfer's ten: 68 of the 72 ordered pairs are available,
    /// and the four that are not are Swedish and Danish against Polish. Both
    /// reach English perfectly well, which is exactly why Konfer does not
    /// quietly hop through it — see ``TranscriptTranslator``.
    case unavailable
}

// MARK: - TranscriptTranslationError

/// Failures translating a transcript.
///
/// Not called `TranslationError`: Apple's framework already has one, and this
/// file has to name both.
nonisolated enum TranscriptTranslationError: LocalizedError {

    case sameLanguage
    case pairUnavailable(from: MeetingLanguage, to: MeetingLanguage)
    case notInstalled(from: MeetingLanguage, to: MeetingLanguage)
    case failed(underlying: Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sameLanguage:
            "This meeting is already in that language."
        case .pairUnavailable(let from, let to):
            "macOS can't translate \(from.displayName) into \(to.displayName)."
        case .notInstalled(let from, let to):
            "\(from.displayName) to \(to.displayName) hasn't been downloaded yet."
        case .failed:
            "Translation failed."
        case .cancelled:
            "Translation was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .pairUnavailable:
            "macOS offers no translation between those two languages, in "
            + "either direction. Translating to English works, and is a better "
            + "record than a translation of a translation."
        case .notInstalled:
            "Download the pair from System Settings ▸ General ▸ Language & "
            + "Region ▸ Translation Languages, or from the Translate sheet."
        case .failed:
            "The recording is untouched. Try translating again."
        default:
            nil
        }
    }

    /// The underlying error, for the detail line in an error banner.
    var underlyingDescription: String? {
        guard case .failed(let error) = self else { return nil }
        return error.localizedDescription
    }
}

// MARK: - TranscriptTranslator

/// Translates a finished transcript, one turn at a time, on this machine.
///
/// An `actor` because `TranslationSession` is a class and not `Sendable`: it is
/// created here, used here and released here, and never crosses an isolation
/// boundary. The same shape ``BackendRegistry`` and the two ASR backends take,
/// and for the same reason.
///
/// Measured on an M3 Ultra, Swedish to English: **0.34 s per turn**, so the 356
/// turns of a 1 h 17 m meeting take about two minutes — a fifth of the 10.3
/// minutes that transcribing it cost. That is why translation is an action you
/// ask for on a finished transcript rather than a fourth stage of the pipeline:
/// it is cheap enough to run twice and far too slow to run unasked.
///
/// The macOS 26.4 `preferredStrategy` initialisers are deliberately not used.
/// They are past the app's deployment target, and a probe of them rejected
/// Swedish outright with `unsupportedSourceLanguage` — which the plain
/// initialiser translates without complaint. Nothing to gain, a language to
/// lose.
actor TranscriptTranslator {

    // MARK: - Availability

    /// Whether this Mac can translate between two of Konfer's languages.
    static func availability(
        from source: MeetingLanguage,
        to target: MeetingLanguage
    ) async -> TranslationAvailability {
        guard source != target else { return .unavailable }

        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: source.code),
            to: Locale.Language(identifier: target.code)
        )

        return switch status {
        case .installed: .ready
        case .supported: .needsDownload
        case .unsupported: .unavailable
        @unknown default: .unavailable
        }
    }

    // MARK: - Translating

    /// Translates the given turns, in order.
    ///
    /// Turns are sent whole rather than sentence by sentence: a turn is the
    /// unit the transcript is made of, the unit an edit invalidates, and enough
    /// context for the model to get pronouns and word order right.
    ///
    /// - Returns: One line per turn that came back, keyed by the turn's id. A
    ///   turn whose translation is empty is left out rather than stored blank.
    func translate(
        _ utterances: [Utterance],
        from source: MeetingLanguage,
        to target: MeetingLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TranslatedLine] {

        guard source != target else { throw TranscriptTranslationError.sameLanguage }
        guard !utterances.isEmpty else { return [] }

        switch await Self.availability(from: source, to: target) {
        case .ready:
            break
        case .needsDownload:
            throw TranscriptTranslationError.notInstalled(from: source, to: target)
        case .unavailable:
            throw TranscriptTranslationError.pairUnavailable(from: source, to: target)
        }

        let session = TranslationSession(
            installedSource: Locale.Language(identifier: source.code),
            target: Locale.Language(identifier: target.code)
        )

        // The id goes out with the request and comes back on the response, so
        // a line is matched to its turn rather than to a position — the
        // batch is ordered today, and nothing in the contract says it must be.
        let byIdentifier = Dictionary(
            utterances.map { ($0.id.uuidString, $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let requests = utterances.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString)
        }

        var lines: [TranslatedLine] = []
        lines.reserveCapacity(requests.count)
        let total = Double(requests.count)

        do {
            for try await response in session.translate(batch: requests) {
                // Checked per response rather than per batch: at a third of a
                // second a turn, that is how long Cancel takes to bite.
                if Task.isCancelled {
                    session.cancel()
                    throw TranscriptTranslationError.cancelled
                }

                if let identifier = response.clientIdentifier,
                   let utteranceID = byIdentifier[identifier],
                   !response.targetText.isEmpty {
                    lines.append(TranslatedLine(utteranceID: utteranceID, text: response.targetText))
                }

                progress(Double(lines.count) / total)
            }
        } catch let error as TranscriptTranslationError {
            throw error
        } catch {
            if TranslationError.notInstalled ~= error {
                throw TranscriptTranslationError.notInstalled(from: source, to: target)
            }
            if error is CancellationError {
                throw TranscriptTranslationError.cancelled
            }
            throw TranscriptTranslationError.failed(underlying: error)
        }

        progress(1)
        return lines
    }
}
