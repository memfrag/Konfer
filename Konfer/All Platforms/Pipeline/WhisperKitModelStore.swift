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

        /// OpenAI's Whisper large-v3. Multilingual; Danish, Dutch and Polish,
        /// and Apple's languages when it is chosen instead.
        case largeV3 = "openai_whisper-large-v3"

        var folderName: String { rawValue }

        /// The Hugging Face repository the folder lives in.
        var repository: String {
            switch self {
            case .largeV3: "argmaxinc/whisperkit-coreml"
            }
        }

        /// What the download costs, for a UI that has to say so before it
        /// starts. Approximate: the exact figure is only known afterwards.
        var estimatedBytes: Int64 {
            switch self {
            case .largeV3: 3_100_000_000
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

    // MARK: - Retired

    /// Where Konfer 1.4 put Røst v3, the Danish model it has since dropped.
    static let retiredRepositories = ["kramerthomas/roest-v3-whisper-1.5b-coreml"]

    /// Deletes what Konfer downloaded for a model it no longer uses.
    ///
    /// Runs on every launch, and finds nothing after the first. Without it
    /// Røst's 1.6 GB would stay on disk for good: the Models window no longer
    /// lists it, so nothing there could delete it, yet Settings ▸ Models would
    /// keep counting it. The repository's folder goes whole — the model and
    /// the hub's `.cache` beside it — and then its owner's, which held nothing
    /// else.
    @discardableResult
    static func removeRetired(from base: URL = KBWhisperModelStore.directory) -> [URL] {
        let fileManager = FileManager.default
        let hub = HubApiWrapper(downloadBase: base)
        var removed: [URL] = []
        for repository in retiredRepositories {
            let folder = hub.localRepoLocation(HubApiWrapper.Repo(id: repository, type: .models))
            guard fileManager.fileExists(atPath: folder.path),
                  (try? fileManager.removeItem(at: folder)) != nil
            else { continue }
            removed.append(folder)

            let owner = folder.deletingLastPathComponent()
            if (try? fileManager.contentsOfDirectory(atPath: owner.path))?.isEmpty == true {
                try? fileManager.removeItem(at: owner)
            }
        }
        return removed
    }
}
