//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import CryptoKit
import Foundation
import Zipcode

/// Downloads and installs Konfer's own CoreML conversion of Pianissimo.
///
/// Klang publishes Pianissimo only as NeMo, ONNX and MLX. The community CoreML
/// conversions all fix the encoder at FluidAudio's 15-second window, and on a
/// real meeting that window cost the model whole phrases its authors' 2-minute
/// chunks keep — "där vi bara gick runt bordet idag", "En kille har byggt".
/// This conversion takes 120 seconds at a time instead, the length Klang's own
/// MLX script uses, with the checkpoint's local attention (±256 frames)
/// reproduced as a band mask over full attention: the same function to 2e-6,
/// but plain masked attention that CoreML can convert.
///
/// Made by `scripts/pianissimo-coreml/convert.sh` and published by its
/// `package.sh` as one zip on Konfer's own GitHub releases, so the models
/// don't depend on anyone's Hugging Face repository staying put. The release
/// is pinned by tag and SHA-256: a replaced asset is refused rather than run
/// in Pianissimo's name.
///
/// Lives beside KB-Whisper under ``KBWhisperModelStore/directory``, so
/// Settings ▸ Models measures and deletes it with the rest.
///
nonisolated enum PianissimoModelStore {

    static let release = "pianissimo-sv-120s-1"
    static let archiveSHA256 = "bf3aa3664c9b9e06cc95a976b40176429f4cb5abd7752ff1db67b7073e036561"

    // swiftlint:disable:next force_unwrapping
    static let archiveURL = URL(
        string: "https://github.com/memfrag/Konfer/releases/download/\(release)/pianissimo-sv-120s.zip"
    )!

    static let components = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    static var directory: URL {
        KBWhisperModelStore.directory.appendingPathComponent("pianissimo-sv-120s", isDirectory: true)
    }

    static func url(for component: String) -> URL {
        directory.appendingPathComponent(component)
    }

    static var isInstalled: Bool {
        isInstalled(at: directory)
    }

    static func isInstalled(at folder: URL) -> Bool {
        components.allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// Fetches and installs the release, unless it is already in place.
    ///
    /// Progress is coarse — the download, then the unpacking — because
    /// URLSession's async download reports nothing until it is done.
    static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isInstalled else { return }

        let (archive, response) = try await URLSession.shared.download(from: archiveURL)
        defer { try? FileManager.default.removeItem(at: archive) }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw PipelineError.modelDownloadFailed(underlying: URLError(.badServerResponse))
        }
        progress(0.9)

        try install(archive: archive, sha256: archiveSHA256, into: directory)
        progress(1)
    }

    /// Checks an archive and unpacks it into `destination`, replacing whatever
    /// was there.
    ///
    /// Unpacks beside the destination first and moves the result into place
    /// only once every entry is out, so a failure never leaves a half-installed
    /// model that ``isInstalled`` would mistake for a whole one.
    static func install(archive: URL, sha256 expected: String, into destination: URL) throws {
        guard try sha256(of: archive) == expected else {
            throw PipelineError.modelDownloadFailed(underlying: URLError(.cannotDecodeContentData))
        }

        let fileManager = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let root = staging.standardizedFileURL.path + "/"
        try ZipArchive(path: archive.path).read { reader in
            for entry in try reader.entries() {
                let target = staging.appendingPathComponent(entry.name).standardizedFileURL
                // An entry named "../something" must not write outside the folder.
                guard target.path.hasPrefix(root) else {
                    throw PipelineError.modelDownloadFailed(underlying: URLError(.cannotDecodeContentData))
                }
                if entry.isDirectory {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fileManager.createDirectory(
                        at: target.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try reader.readEntry(entry, to: target.path)
                }
            }
        }
        guard isInstalled(at: staging) else {
            throw PipelineError.modelDownloadFailed(underlying: URLError(.cannotDecodeContentData))
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
    }

    static func remove() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Streamed, because the archive is 630 MB.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
