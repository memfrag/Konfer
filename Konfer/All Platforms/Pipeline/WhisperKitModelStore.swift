//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import WhisperKit

/// Models fetched by WhisperKit's own downloader.
///
/// The counterpart to ``KBWhisperModelStore``, and the reason both exist:
/// KB-Whisper is published as plain `small/` and `large/` folders, which
/// WhisperKit's downloader cannot find, so that store fetches a hardcoded list
/// of files by hand. Stock Whisper lives in `argmaxinc/whisperkit-coreml`,
/// which *is* WhisperKit's own layout — and whose folders carry files the
/// hardcoded list doesn't have — so here we let WhisperKit do it.
///
/// Both write beneath ``KBWhisperModelStore/directory``, so Settings ▸ Models
/// measures and deletes everything in one place.
///
nonisolated enum WhisperKitModelStore {

    /// The compiled CoreML bundles every Whisper model folder has. Used only to
    /// tell a finished download from an interrupted one — the full file list is
    /// WhisperKit's business, not ours.
    private static let requiredBundles = [
        "AudioEncoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "TextDecoder.mlmodelc",
    ]

    // MARK: - Variant

    enum Variant: String, Sendable, CaseIterable {

        /// OpenAI's Whisper large-v3. Multilingual; Dutch and Polish, and
        /// Danish when Røst isn't wanted.
        case largeV3 = "openai_whisper-large-v3"

        /// Røst v3, the CoRal project's Danish fine-tune of large-v3, as an
        /// 8-bit WhisperKit conversion. Same architecture and vocabulary as
        /// large-v3, so the same tokenizer.
        case roestV3 = "CoRal-project_roest-v3-whisper-1.5b_1624MB"

        var folderName: String { rawValue }

        /// The Hugging Face repository the folder lives in.
        var repository: String {
            switch self {
            case .largeV3: "argmaxinc/whisperkit-coreml"
            case .roestV3: "kramerthomas/roest-v3-whisper-1.5b-coreml"
            }
        }

        /// The commit to fetch, or nil for the repository's latest.
        ///
        /// Røst is pinned because it is one person's conversion: a later push
        /// to that repository shouldn't change what Konfer transcribes with,
        /// or what it has already told people they're downloading. Argmax's
        /// own repository is the one WhisperKit itself tracks.
        var revision: String? {
            switch self {
            case .largeV3: nil
            case .roestV3: "3e9222be085107e7843c738c0078522644c5afeb"
            }
        }

        /// What the download costs, for a UI that has to say so before it
        /// starts. Approximate: the exact figure is only known afterwards.
        var estimatedBytes: Int64 {
            switch self {
            case .largeV3: 3_100_000_000
            case .roestV3: 1_630_000_000
            }
        }
    }

    // MARK: - Location

    /// Where WhisperKit's downloader puts this repository's snapshots.
    ///
    /// Derived from WhisperKit rather than assumed, so a change to its cache
    /// layout moves our lookups with it instead of silently missing them.
    static func directory(for variant: Variant) -> URL {
        HubApiWrapper(downloadBase: KBWhisperModelStore.directory)
            .localRepoLocation(HubApiWrapper.Repo(id: variant.repository, type: .models))
            .appending(path: variant.folderName)
    }

    static func isDownloaded(_ variant: Variant) -> Bool {
        let root = directory(for: variant)
        return requiredBundles.allSatisfy {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    // MARK: - Download

    /// Fetches the model, reporting progress in [0, 1].
    ///
    /// - Note: WhisperKit resumes at snapshot granularity rather than per file,
    ///   so an interrupted 3 GB download restarts. That is the price of not
    ///   hardcoding a file list we cannot keep in step with the repository.
    @discardableResult
    static func download(
        _ variant: Variant,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        do {
            // WhisperKit's own download has no way to name a commit, so a
            // pinned variant is fetched through the hub wrapper underneath it,
            // which lands it in the same place.
            if let revision = variant.revision {
                let snapshot = try await HubApiWrapper(downloadBase: KBWhisperModelStore.directory)
                    .snapshot(
                        from: HubApiWrapper.Repo(id: variant.repository, type: .models),
                        revision: revision,
                        matching: ["\(variant.folderName)/*"]
                    ) { fraction in
                        progress(fraction.fractionCompleted)
                    }
                return snapshot.appending(path: variant.folderName)
            }
            return try await WhisperKit.download(
                variant: variant.folderName,
                downloadBase: KBWhisperModelStore.directory,
                from: variant.repository
            ) { fraction in
                progress(fraction.fractionCompleted)
            }
        } catch {
            throw PipelineError.modelDownloadFailed(underlying: error)
        }
    }

    static func remove(_ variant: Variant) throws {
        let root = directory(for: variant)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    static func sizeOnDisk(_ variant: Variant) -> Int64 {
        ModelStorage.size(of: directory(for: variant))
    }
}
