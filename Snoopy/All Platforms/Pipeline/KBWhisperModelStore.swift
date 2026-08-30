//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Downloads the KB-Whisper CoreML bundles WhisperKit needs.
///
/// WhisperKit can fetch models itself, but only from repositories laid out to
/// its own naming convention. KB-Whisper is published as plain `small/` and
/// `large/` folders, so Snoopy fetches the handful of files itself and points
/// WhisperKit at the resulting directory with `modelFolder`.
///
nonisolated enum KBWhisperModelStore {

    /// The files that make up one WhisperKit model folder.
    private static let fileNames = [
        "AudioEncoder.mlmodelc/coremldata.bin",
        "AudioEncoder.mlmodelc/metadata.json",
        "AudioEncoder.mlmodelc/model.mil",
        "AudioEncoder.mlmodelc/analytics/coremldata.bin",
        "AudioEncoder.mlmodelc/weights/weight.bin",
        "MelSpectrogram.mlmodelc/coremldata.bin",
        "MelSpectrogram.mlmodelc/metadata.json",
        "MelSpectrogram.mlmodelc/model.mil",
        "MelSpectrogram.mlmodelc/analytics/coremldata.bin",
        "MelSpectrogram.mlmodelc/weights/weight.bin",
        "TextDecoder.mlmodelc/coremldata.bin",
        "TextDecoder.mlmodelc/metadata.json",
        "TextDecoder.mlmodelc/model.mil",
        "TextDecoder.mlmodelc/analytics/coremldata.bin",
        "TextDecoder.mlmodelc/weights/weight.bin",
        "config.json",
        "generation_config.json",
    ]

    private static let repository = "mickekringai/kb-whisper-coreml"

    /// Root for every KB-Whisper variant, alongside FluidAudio's own cache.
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("Snoopy", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static func directory(for variant: Variant) -> URL {
        directory.appendingPathComponent(variant.folderName, isDirectory: true)
    }

    static func isDownloaded(_ variant: Variant) -> Bool {
        let root = directory(for: variant)
        return fileNames.allSatisfy {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    /// Fetches whatever is missing. Existing files are left alone, so an
    /// interrupted download resumes at file granularity on the next attempt.
    static func download(
        _ variant: Variant,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {

        let root = directory(for: variant)
        let fileManager = FileManager.default
        var completed = 0

        for name in fileNames {
            let destination = root.appendingPathComponent(name)
            defer {
                completed += 1
                progress(Double(completed) / Double(fileNames.count))
            }
            if fileManager.fileExists(atPath: destination.path) { continue }

            guard let source = URL(
                string: "https://huggingface.co/\(repository)/resolve/main/\(variant.folderName)/\(name)"
            ) else { continue }

            let (temporary, response) = try await URLSession.shared.download(from: source)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                try? fileManager.removeItem(at: temporary)
                throw PipelineError.modelDownloadFailed(
                    underlying: URLError(.badServerResponse)
                )
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Move into place only once the file is complete, so a crash can't
            // leave a truncated model that later fails to compile.
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    static func sizeOnDisk() -> Int64 {
        ModelStorage.size(of: directory)
    }

    static func removeAll() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Variant

    enum Variant: String, Sendable {
        case small
        case large

        var folderName: String { rawValue }
    }
}
