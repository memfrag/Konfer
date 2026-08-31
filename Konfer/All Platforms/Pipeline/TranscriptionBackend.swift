//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - TranscribedAudio

/// The result of running speech recognition over a file.
nonisolated struct TranscribedAudio: Sendable {
    let text: String
    let words: [WordSpan]

    /// Where the recording was cut into slices, if it was. Kept so the player
    /// can show them: a cut that lands in the middle of someone talking is the
    /// evidence that the automatic placement needs help, and it is invisible
    /// otherwise.
    var sliceCuts: [TimeInterval] = []
}

// MARK: - TranscriptionRequest

/// Everything a backend needs to transcribe one recording.
///
/// A struct rather than a parameter list because the interesting part of this
/// app is what gets passed here, and that keeps growing.
nonisolated struct TranscriptionRequest: Sendable {

    let url: URL

    /// The language the user declared for the meeting. Backends that can be
    /// pinned to a language should honour it; Whisper in particular detects
    /// language *per chunk* when left to itself, which on a Swedish meeting
    /// full of English loanwords makes it flip mid-file.
    let language: MeetingLanguage

    /// Where the diarizer found speech, so a backend that chunks can cut on
    /// real silence instead of guessing. Backends are free to ignore it.
    let speechRegions: [SpeechRegion]

    /// Whether the user has accepted a faster but incomplete transcript.
    /// Off by default — see ``WhisperKitBackend/chunkingStrategy(allowed:)``.
    let allowsChunking: Bool
}

// MARK: - TranscriptionBackend

/// Speech recognition, behind a protocol.
///
/// The swap point: a language specialist (KB-Whisper for Swedish) sits beside a
/// generalist (Apple, stock Whisper) without diarization, alignment or anything
/// above them knowing which is running.
///
/// Implementations are used from a background context, so they must not be
/// `@MainActor`. Note that this app builds with default-`MainActor` isolation,
/// which makes that an explicit decision rather than the default.
///
nonisolated protocol TranscriptionBackend: Sendable {

    /// Downloads and loads models if needed. Safe to call repeatedly.
    ///
    /// Takes the language because readiness is not always a single fact about
    /// the backend: Apple installs its models **per locale**, so a backend
    /// ready for English may still have to fetch German. Backends bound to one
    /// model ignore it.
    func prepare(
        for language: MeetingLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws

    /// Whether models for this language are already resident, so callers can
    /// skip a preparation stage in the UI.
    func isPrepared(for language: MeetingLanguage) async -> Bool

    /// Releases loaded models, e.g. before deleting them from disk.
    func unload() async

    func transcribe(
        _ request: TranscriptionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio
}
