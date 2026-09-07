//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import CoreMedia
import Foundation

// MARK: - Errors

nonisolated enum VideoExportError: LocalizedError {

    case notAVideo(URL)
    case unreadable(URL, underlying: Error)
    case trackCreationFailed
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAVideo(let url):
            "\(url.lastPathComponent) has no video to put subtitles on."
        case .unreadable(let url, _):
            "Couldn't read \(url.lastPathComponent)."
        case .trackCreationFailed:
            "Couldn't add a subtitle track to the copy."
        case .writeFailed:
            "Couldn't write the subtitled copy."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notAVideo:
            "Subtitles need a picture to sit on. This meeting was recorded as audio only."
        case .unreadable:
            "The recording may have moved, or may be in a format Konfer can't open."
        default:
            nil
        }
    }
}

// MARK: - SubtitledVideoWriter

/// Writes a copy of a recording with the transcript embedded as a subtitle track.
///
/// QuickTime Player, unlike VLC or IINA, will not pick up a `.srt` sitting next
/// to a movie. The only way its Subtitles menu offers anything is for the
/// subtitles to be inside the file — so this writes a second copy carrying a
/// tx3g track. Nothing is re-encoded: the video and audio samples are copied
/// across verbatim, which is why an hour of screen recording costs disk and
/// patience but not quality.
///
/// The user's own recording is never touched. That is the rule the whole
/// library is built on — see ``LibraryLocation``.
///
/// **What makes the subtitles actually appear.** Four things, each of which
/// was found the hard way against QuickTime, and none of which it reports:
///
/// 1. `appendSampleBuffer` grows a track's *media*; it does not put that media
///    on the track's *timeline*. Without ``AVMutableMovieTrack/insertMediaTimeRange(_:into:)``
///    the track header says duration zero, and a player lists the subtitles in
///    its menu and then never draws one. This was the whole bug.
/// 2. Both language properties, set before the header is written: `mdhd`
///    carries the ISO 639-2/T code, and without it the track reads as `und`.
/// 3. `.addMovieHeaderToDestination` when writing. The truncating option throws
///    away sample data already copied into the same file — `AVMovie.h` warns
///    about exactly this, and it turns the video into unparseable garbage.
/// 4. The sample description matched to what a known-good file uses: no display
///    flags, an opaque background, and no default text box, letting the player
///    place the text over the picture itself.
///
nonisolated enum SubtitledVideoWriter {

    /// Media timescale for the subtitle track. 600 is the traditional QuickTime
    /// value, divisible by every common frame rate.
    private static let timescale: CMTimeScale = 600

    /// Copied in slices so there is something to report; whole-file inserts are
    /// a single opaque call that can run for minutes on a long recording.
    private static let chunkDuration: TimeInterval = 30

    /// Roughly 3% of the picture's height, which reads at 1080p and stays
    /// proportionate on 4K. Floored because tx3g carries the size in one byte.
    private static func fontSize(for height: CGFloat) -> Int {
        max(16, min(127, Int(height * 0.033)))
    }

    // MARK: - Writing

    /// - Parameters:
    ///   - trimmed: Whether to cut the copy to the meeting's kept range. Cue
    ///     times are shifted with it, so the subtitles still land on the words.
    ///   - rendering: Which language the subtitle track carries. A translated
    ///     track is tagged with the language it is in, not the one the meeting
    ///     was held in, so a player's Subtitles menu names it correctly.
    ///   - progress: Fraction complete, 0...1, called as the copy proceeds.
    static func write(
        meeting: Meeting,
        to destination: URL,
        trimmed: Bool,
        rendering: TranscriptRendering = .original,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {

        let source = meeting.audioURL
        let asset = AVURLAsset(url: source)

        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        let sourceDuration: TimeInterval
        do {
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
            sourceDuration = try await asset.load(.duration).seconds
        } catch {
            throw VideoExportError.unreadable(source, underlying: error)
        }
        guard let firstVideo = videoTracks.first else {
            throw VideoExportError.notAVideo(source)
        }
        let pictureSize = try await firstVideo.load(.naturalSize)

        // What to copy, and where the copy's clock starts relative to the
        // recording's — everything else is measured from that offset.
        let kept = trimmed ? meeting.keptRange : nil
        let start = kept?.start ?? 0
        let end = min(kept?.end ?? sourceDuration, sourceDuration)
        let span = max(0, end - start)

        try? FileManager.default.removeItem(at: destination)

        let movie = AVMutableMovie()
        movie.defaultMediaDataStorage = AVMediaDataStorage(url: destination, options: nil)

        try await copyTracks(
            videoTracks + audioTracks,
            into: movie,
            from: start,
            length: span,
            progress: progress
        )

        try addSubtitles(
            to: movie,
            meeting: meeting,
            rendering: rendering,
            offset: start,
            length: span,
            pictureSize: pictureSize
        )

        do {
            try movie.writeHeader(
                to: destination,
                fileType: fileType(matching: source),
                options: .addMovieHeaderToDestination
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw VideoExportError.writeFailed(underlying: error)
        }
        progress(1)
    }

    /// A copy of a `.mp4` stays a `.mp4`. Both containers carry a tx3g track
    /// and both play in QuickTime; changing a file's kind on the way through
    /// would just be surprising.
    private static func fileType(matching source: URL) -> AVFileType {
        switch source.pathExtension.lowercased() {
        case "mp4", "m4v": .mp4
        default: .mov
        }
    }

    // MARK: - Copying picture and sound

    private static func copyTracks(
        _ tracks: [AVAssetTrack],
        into movie: AVMutableMovie,
        from start: TimeInterval,
        length: TimeInterval,
        progress: @Sendable (Double) -> Void
    ) async throws {

        // The subtitle track is quick; the copy is all of the wait, so it owns
        // almost all of the bar.
        let copyShare = 0.97
        let chunks = max(1, Int((length / chunkDuration).rounded(.up)))
        let total = Double(chunks * tracks.count)
        var done = 0.0

        for track in tracks {
            guard let copy = movie.addMutableTrack(
                withMediaType: track.mediaType, copySettingsFrom: track, options: nil
            ) else { throw VideoExportError.trackCreationFailed }

            for chunk in 0..<chunks {
                try Task.checkCancellation()

                let offset = Double(chunk) * chunkDuration
                let piece = min(chunkDuration, length - offset)
                guard piece > 0 else { break }

                let sourceRange = CMTimeRange(
                    start: CMTime(seconds: start + offset, preferredTimescale: timescale),
                    duration: CMTime(seconds: piece, preferredTimescale: timescale)
                )
                do {
                    // Appended at the end of what has been copied so far, so
                    // successive slices meet without a gap.
                    try copy.insertTimeRange(
                        sourceRange,
                        of: track,
                        at: CMTime(seconds: offset, preferredTimescale: timescale),
                        copySampleData: true
                    )
                } catch {
                    throw VideoExportError.writeFailed(underlying: error)
                }

                done += 1
                progress(done / total * copyShare)
            }
        }
    }

    // MARK: - The subtitle track

    private static func addSubtitles(
        to movie: AVMutableMovie,
        meeting: Meeting,
        rendering: TranscriptRendering,
        offset: TimeInterval,
        length: TimeInterval,
        pictureSize: CGSize
    ) throws {

        let format = try formatDescription(fontSize: fontSize(for: pictureSize.height))

        guard let track = movie.addMutableTrack(
            withMediaType: .subtitle, copySettingsFrom: nil, options: nil
        ) else { throw VideoExportError.trackCreationFailed }

        // The language on the track is the language of the words on it, which
        // for a translated copy is not the language of the meeting. A player's
        // Subtitles menu reads these and would otherwise offer "Swedish" over
        // a track of English.
        let spoken = rendering == .translated
            ? (meeting.translationTarget ?? meeting.language)
            : meeting.language

        // Both, and before the header is written: `mdhd` carries the three
        // letter code and is what a player reads to label the track.
        track.languageCode = iso639_2(for: spoken)
        track.extendedLanguageTag = spoken.code
        // Its own alternate group, so the track is offered as a subtitle choice
        // rather than as an alternative to the picture or the sound.
        track.alternateGroupID = 3
        track.isEnabled = true

        // The same cues SubRip gets, shifted onto the copy's clock. The name
        // takes room on the line here exactly as it does there.
        let cues = SubtitleExporter.cues(
            for: meeting, attributionTakesRoom: true, rendering: rendering
        )
            .map {
                (start: $0.start - offset, end: $0.end - offset,
                 text: SubtitleExporter.displayText(for: $0))
            }
            .filter { $0.end > 0 && $0.start < length }

        // A subtitle track with holes in it is a common reason for nothing
        // appearing, so the gaps are filled with empty samples.
        var clock: TimeInterval = 0
        for cue in cues {
            let from = max(0, cue.start)
            let to = min(length, cue.end)
            guard to > from else { continue }
            if from > clock {
                try append("", from: clock, to: from, format: format, to: track)
            }
            try append(cue.text, from: from, to: to, format: format, to: track)
            clock = to
        }
        if clock < length {
            try append("", from: clock, to: length, format: format, to: track)
        }

        // Appending grows the media. This is what puts it on the timeline —
        // without it the track header says duration zero and nothing is ever
        // drawn. See the note on this type.
        let span = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: length, preferredTimescale: timescale)
        )
        guard track.insertMediaTimeRange(span, into: span) else {
            throw VideoExportError.trackCreationFailed
        }
    }

    private static func append(
        _ text: String,
        from start: TimeInterval,
        to end: TimeInterval,
        format: CMFormatDescription,
        to track: AVMutableMovieTrack
    ) throws {
        let sample = try sampleBuffer(text, from: start, to: end, format: format)
        do {
            try track.append(sample, decodeTime: nil, presentationTime: nil)
        } catch {
            throw VideoExportError.writeFailed(underlying: error)
        }
    }

    // MARK: - tx3g

    /// The sample description, matched to what players actually render.
    ///
    /// No display flags, an opaque background and an empty default text box:
    /// with a box of its own the text is laid out inside that rectangle, and
    /// with none the player puts it over the picture where subtitles belong.
    private static func formatDescription(fontSize: Int) throws -> CMFormatDescription {
        let white: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: 255,
            kCMTextFormatDescriptionColor_Green: 255,
            kCMTextFormatDescriptionColor_Blue: 255,
            kCMTextFormatDescriptionColor_Alpha: 255
        ]
        let black: [CFString: Any] = [
            kCMTextFormatDescriptionColor_Red: 0,
            kCMTextFormatDescriptionColor_Green: 0,
            kCMTextFormatDescriptionColor_Blue: 0,
            kCMTextFormatDescriptionColor_Alpha: 255
        ]
        let extensions: [CFString: Any] = [
            kCMTextFormatDescriptionExtension_DisplayFlags: 0,
            kCMTextFormatDescriptionExtension_BackgroundColor: black,
            kCMTextFormatDescriptionExtension_DefaultTextBox: [
                kCMTextFormatDescriptionRect_Top: 0,
                kCMTextFormatDescriptionRect_Left: 0,
                kCMTextFormatDescriptionRect_Bottom: 0,
                kCMTextFormatDescriptionRect_Right: 0
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_DefaultStyle: [
                kCMTextFormatDescriptionStyle_StartChar: 0,
                kCMTextFormatDescriptionStyle_EndChar: 0,
                kCMTextFormatDescriptionStyle_Font: 1,
                kCMTextFormatDescriptionStyle_FontFace: 0,
                kCMTextFormatDescriptionStyle_ForegroundColor: white,
                kCMTextFormatDescriptionStyle_FontSize: fontSize
            ] as [CFString: Any],
            kCMTextFormatDescriptionExtension_FontTable: ["1": "Helvetica"] as [CFString: Any],
            kCMTextFormatDescriptionExtension_HorizontalJustification:
                Int(kCMTextJustification_centered),
            kCMTextFormatDescriptionExtension_VerticalJustification:
                Int(kCMTextJustification_bottom_right)
        ]

        var format: CMFormatDescription?
        let status = CMFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            mediaType: kCMMediaType_Subtitle,
            mediaSubType: kCMSubtitleFormatType_3GText,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &format
        )
        guard status == noErr, let format else {
            throw VideoExportError.trackCreationFailed
        }
        return format
    }

    /// A tx3g sample: two bytes of big-endian text length, then UTF-8.
    /// Per 3GPP TS 26.245. An empty sample is the two zero bytes alone.
    static func payload(for text: String) -> Data {
        let utf8 = Array(text.utf8)
        let count = min(utf8.count, Int(UInt16.max))
        var data = Data([UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)])
        data.append(contentsOf: utf8.prefix(count))
        return data
    }

    private static func sampleBuffer(
        _ text: String,
        from start: TimeInterval,
        to end: TimeInterval,
        format: CMFormatDescription
    ) throws -> CMSampleBuffer {

        let bytes = payload(for: text)

        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        )
        guard status == noErr, let block else { throw VideoExportError.trackCreationFailed }

        try bytes.withUnsafeBytes { raw in
            let copied = CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: block,
                offsetIntoDestination: 0, dataLength: bytes.count
            )
            guard copied == noErr else { throw VideoExportError.trackCreationFailed }
        }

        var timing = CMSampleTimingInfo(
            duration: CMTime(seconds: end - start, preferredTimescale: timescale),
            presentationTimeStamp: CMTime(seconds: start, preferredTimescale: timescale),
            decodeTimeStamp: .invalid
        )
        var length = bytes.count
        var buffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &length, sampleBufferOut: &buffer
        )
        guard status == noErr, let buffer else { throw VideoExportError.trackCreationFailed }
        return buffer
    }

    /// `mdhd` wants ISO 639-2/T, three letters, where ``MeetingLanguage/code``
    /// is the two-letter BCP-47 tag.
    private static func iso639_2(for language: MeetingLanguage) -> String {
        Locale(identifier: language.code).language.languageCode?
            .identifier(.alpha3) ?? "und"
    }
}
