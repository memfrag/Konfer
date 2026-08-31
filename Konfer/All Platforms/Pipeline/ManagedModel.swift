//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

/// A model Konfer downloads and manages itself.
///
/// Three models arrive by three different mechanisms — FluidAudio loads its own
/// from Hugging Face, KB-Whisper is fetched file by file because its repository
/// is not in WhisperKit's layout, and stock Whisper is fetched by WhisperKit —
/// and until now nothing knew about all three at once. Downloads happened as a
/// side effect of transcribing, so "what does Konfer need, and what does it
/// already have" was a question no single type could answer.
///
/// This is that type. It backs the downloads window, the first-run offer, and
/// the check that stops a run before it discovers three gigabytes are missing.
///
/// Apple's languages are deliberately absent: macOS installs those assets
/// itself, per locale, and there is nothing here for us to host, measure or
/// delete. See ``AppleSpeechBackend``.
///
nonisolated enum ManagedModel: String, CaseIterable, Identifiable, Sendable {

    /// pyannote segmentation and WeSpeaker embeddings, via FluidAudio. Needed
    /// by every transcription, whatever the language.
    case diarization

    /// The National Library of Sweden's Whisper fine-tune. Swedish only.
    case kbWhisperLarge

    /// Stock multilingual Whisper. Danish, Dutch and Polish.
    case whisperLargeV3

    var id: String { rawValue }

    // MARK: - Description

    var displayName: String {
        switch self {
        case .diarization: "Speaker identification"
        case .kbWhisperLarge: "KB-Whisper Large"
        case .whisperLargeV3: "Whisper Large v3"
        }
    }

    var summary: String {
        switch self {
        case .diarization:
            "Works out who spoke when. Every transcription uses it, whatever "
            + "the language."
        case .kbWhisperLarge:
            "Transcribes Swedish. Trained on more than 50,000 hours of it by "
            + "the National Library of Sweden."
        case .whisperLargeV3:
            "Transcribes Danish, Dutch and Polish, which neither Apple nor "
            + "KB-Whisper can do."
        }
    }

    /// The languages that need this model, empty for one that everything needs.
    var languages: [MeetingLanguage] {
        switch self {
        case .diarization:
            []
        case .kbWhisperLarge, .whisperLargeV3:
            MeetingLanguage.allCases.filter { ManagedModel(transcribing: $0) == self }
        }
    }

    /// What the download costs, for a UI that must say so before starting it.
    /// Approximate — the exact figure is only known once it is on disk.
    var estimatedBytes: Int64 {
        switch self {
        case .diarization: 22_000_000
        case .kbWhisperLarge: 2_900_000_000
        case .whisperLargeV3: WhisperKitModelStore.Variant.largeV3.estimatedBytes
        }
    }

    // MARK: - Routing

    /// The model a language needs Konfer to have downloaded, or `nil` when it
    /// needs none — which is the case for every language Apple covers.
    ///
    /// Deliberately *not* about diarization, which every language needs: this
    /// answers "what must be fetched before this recording can be transcribed",
    /// and diarization is not gated. See ``ModelDownloadQueue``.
    init?(transcribing language: MeetingLanguage) {
        switch ASRBackendKind(transcribing: language) {
        case .appleSpeech: return nil
        case .kbWhisperLarge: self = .kbWhisperLarge
        case .whisperLargeV3: self = .whisperLargeV3
        case .kbWhisperSmall: return nil
        }
    }

    // MARK: - State on disk

    /// Checked cheaply — file existence only, never a tree walk. Views call
    /// this while rendering, and ``sizeOnDisk()`` is what costs.
    var isInstalled: Bool {
        switch self {
        case .diarization: ModelStorage.isPopulated
        case .kbWhisperLarge: KBWhisperModelStore.isDownloaded(.large)
        case .whisperLargeV3: WhisperKitModelStore.isDownloaded(.largeV3)
        }
    }

    /// Bytes actually used, once installed.
    ///
    /// Walks the model's directory, so read it once and hold the result rather
    /// than calling it from a view body.
    func sizeOnDisk() -> Int64 {
        switch self {
        case .diarization: ModelStorage.sizeOnDisk()
        case .kbWhisperLarge: ModelStorage.size(of: KBWhisperModelStore.directory(for: .large))
        case .whisperLargeV3: WhisperKitModelStore.sizeOnDisk(.largeV3)
        }
    }

    // MARK: - Fetching

    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        switch self {
        case .diarization:
            // FluidAudio has no download-only call: `load` fetches *and* loads
            // into memory. Pre-fetching therefore costs a load we don't need,
            // so the models are released again immediately — the pipeline
            // reloads them from disk in about a second when a run starts.
            let service = DiarizationService()
            try await service.prepare(progress: progress)
            await service.unload()

        case .kbWhisperLarge:
            try await KBWhisperModelStore.download(.large, progress: progress)

        case .whisperLargeV3:
            try await WhisperKitModelStore.download(.largeV3, progress: progress)
        }
    }

    func remove() throws {
        switch self {
        case .diarization: try ModelStorage.removeAll()
        case .kbWhisperLarge: try KBWhisperModelStore.remove(.large)
        case .whisperLargeV3: try WhisperKitModelStore.remove(.largeV3)
        }
    }
}
