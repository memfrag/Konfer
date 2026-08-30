//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Foundation

/// The audio file handed to FluidAudio, plus how to clean up after it.
nonisolated struct PreparedAudio: Sendable {

    /// The file the pipeline should read. Either the user's own file or, for
    /// video input, a temporary audio-only extraction of it.
    let url: URL

    /// Length of the recording, used for the player and the library row.
    let duration: TimeInterval

    /// Set when `url` is a temporary file this run created.
    let temporaryFile: URL?

    func cleanUp() {
        guard let temporaryFile else { return }
        try? FileManager.default.removeItem(at: temporaryFile)
    }
}

/// Normalizes whatever the user dropped into something FluidAudio can open.
///
/// Both `AudioConverter.resampleAudioFile` and `AudioSourceFactory` open files
/// with `AVAudioFile`, which reads audio containers but not video ones. Since
/// video input is in scope, a video file has its audio track exported to a
/// temporary `.m4a` first; everything downstream then sees a plain audio file
/// and knows nothing about video.
///
nonisolated enum AudioSourcePreparer {

    static func prepare(_ url: URL) async throws -> PreparedAudio {

        let asset = AVURLAsset(url: url)

        let duration: TimeInterval
        do {
            duration = try await asset.load(.duration).seconds
        } catch {
            throw PipelineError.audioUnreadable(url, underlying: error)
        }

        let hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty
        guard hasVideo else {
            return PreparedAudio(url: url, duration: duration, temporaryFile: nil)
        }

        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw PipelineError.noAudioTrack(url)
        }

        let extracted = try await extractAudio(from: asset, named: url.lastPathComponent)
        return PreparedAudio(url: extracted, duration: duration, temporaryFile: extracted)
    }

    private static func extractAudio(
        from asset: AVURLAsset,
        named name: String
    ) async throws -> URL {

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Snoopy-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PipelineError.noAudioTrack(asset.url)
        }

        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw PipelineError.audioUnreadable(asset.url, underlying: error)
        }

        return destination
    }
}
