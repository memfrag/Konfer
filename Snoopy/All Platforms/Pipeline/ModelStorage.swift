//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The on-disk CoreML models FluidAudio downloads from Hugging Face.
///
/// Everything lands in `~/Library/Application Support/FluidAudio/Models/`,
/// one subdirectory per model repository. Snoopy is not sandboxed, so that is
/// the real path in the user's Library rather than a container.
///
/// These are large — hundreds of megabytes — so the Models settings tab shows
/// what they cost and offers to delete them.
///
nonisolated enum ModelStorage {

    /// Root of everything FluidAudio caches for ASR and diarization.
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: directory.path)
    }

    /// Total bytes on disk, or zero when nothing has been downloaded.
    static func sizeOnDisk() -> Int64 {
        size(of: directory)
    }

    /// Bytes used by a directory tree.
    ///
    /// Walks the tree because the model bundles are directories; this touches
    /// a few thousand files at most, and only when the settings tab is open.
    static func size(of directory: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
            )
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Deletes every downloaded model. They are re-downloaded on the next run.
    static func removeAll() throws {
        guard exists else { return }
        try FileManager.default.removeItem(at: directory)
    }

    static func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
