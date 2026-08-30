//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - TranscribedAudio

/// The result of running speech recognition over a file.
nonisolated struct TranscribedAudio: Sendable {
    let text: String
    let words: [WordSpan]
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
/// Parakeet v3 handles both Swedish and English, but its published Swedish word
/// error rate is roughly three times its English one, and real meeting audio is
/// worse than the benchmark. This protocol is the swap point: a Swedish
/// specialist (KB-Whisper via WhisperKit, say) can replace the backend without
/// touching diarization, alignment, or anything above them.
///
/// Implementations are used from a background context, so they must not be
/// `@MainActor`. Note that this app builds with default-`MainActor` isolation,
/// which makes that an explicit decision rather than the default.
///
nonisolated protocol TranscriptionBackend: Sendable {

    /// Downloads and loads models if needed. Safe to call repeatedly.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws

    /// Whether models are already resident, so callers can skip a preparation
    /// stage in the UI.
    var isPrepared: Bool { get async }

    /// Releases loaded models, e.g. before deleting them from disk.
    func unload() async

    func transcribe(
        _ request: TranscriptionRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscribedAudio
}
