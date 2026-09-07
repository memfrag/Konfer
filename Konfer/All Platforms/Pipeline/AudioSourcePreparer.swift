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

    /// Length of `url` — the trimmed extract when there is one, so the stages
    /// reading it report progress against what they actually process.
    let duration: TimeInterval

    /// Length of the file the user chose, which is what the meeting records:
    /// the library points at their recording, whole, however little of it was
    /// transcribed.
    let sourceDuration: TimeInterval

    /// Where the prepared audio begins within the source, so the pipeline can
    /// put the timestamps back where they belong. Zero unless trimmed.
    let startOffset: TimeInterval

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

    /// - Parameter trimmedTo: The stretch to transcribe, or nil for all of it.
    ///   A trim always goes through the export path, audio or video, because
    ///   the stages downstream take a file and have nowhere to put a range.
    static func prepare(
        _ url: URL,
        trimmedTo trim: KeptRange? = nil
    ) async throws -> PreparedAudio {

        let asset = AVURLAsset(url: url)

        let sourceDuration: TimeInterval
        do {
            sourceDuration = try await asset.load(.duration).seconds
        } catch {
            throw PipelineError.audioUnreadable(url, underlying: error)
        }

        let hasVideo = try await !asset.loadTracks(withMediaType: .video).isEmpty
        guard hasVideo || trim != nil else {
            return PreparedAudio(
                url: url,
                duration: sourceDuration,
                sourceDuration: sourceDuration,
                startOffset: 0,
                temporaryFile: nil
            )
        }

        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw PipelineError.noAudioTrack(url)
        }

        // Clamped to the file: a range dragged to the very end can name a
        // moment a fraction past the last sample, and an export session given
        // one fails rather than shrugging.
        let range = trim.map {
            KeptRange(
                start: max(0, min($0.start, sourceDuration)),
                end: max(0, min($0.end, sourceDuration))
            )
        }

        let extracted = try await extractAudio(from: asset, trimmedTo: range)
        return PreparedAudio(
            url: extracted,
            duration: range.map(\.duration) ?? sourceDuration,
            sourceDuration: sourceDuration,
            startOffset: range?.start ?? 0,
            temporaryFile: extracted
        )
    }

    private static func extractAudio(
        from asset: AVURLAsset,
        trimmedTo range: KeptRange?
    ) async throws -> URL {

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Konfer-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw PipelineError.noAudioTrack(asset.url)
        }

        if let range {
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: range.start, preferredTimescale: 600),
                end: CMTime(seconds: range.end, preferredTimescale: 600)
            )
        }

        do {
            try await session.export(to: destination, as: .m4a)
        } catch {
            throw PipelineError.audioUnreadable(asset.url, underlying: error)
        }

        return destination
    }
}
