//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import AudioToolbox
import CryptoKit
import Foundation

/// Gives a recording a name that says what is in it.
///
/// `AVAudioFile` chooses its parser by extension and looks no further. Handed
/// AAC named `.mp3` — a raw ADTS stream, which is what some phone recorders
/// and downloaders save — it refuses to open, while `AVURLAsset` beside it
/// sniffs the bytes, reports a duration and makes the file look fine. Measured
/// on WAV, FLAC, Ogg, ADTS and M4A files all named `.mp3`: none opens, every
/// one opens once the name is right, and the M4A is refused by `AVURLAsset`
/// too.
///
/// AudioToolbox will say what a file is when it is not told the name — opened
/// through callbacks with no type hint — so the user's file is never renamed.
/// A symbolic link with the right extension is made in the temporary directory
/// and read instead; FluidAudio, WhisperKit and `SpeechAnalyzer` all open by
/// URL, and every one of them then sees an ordinary file.
nonisolated enum AudioFileName {

    /// `url` itself, or a link to it whose extension matches its contents.
    ///
    /// Only a file `AVAudioFile` refuses is examined, so a correctly named one
    /// costs a single open — 20 ms for an hour of MP3. A file nothing
    /// recognises comes back unchanged, to fail wherever it would have.
    static func readable(_ url: URL) -> URL {
        guard url.isFileURL,
              (try? AVAudioFile(forReading: url)) == nil,
              let extensions = detectedExtensions(of: url),
              let correct = extensions.first,
              !extensions.contains(url.pathExtension.lowercased()),
              let link = try? link(to: url, extension: correct),
              (try? AVAudioFile(forReading: link)) != nil
        else { return url }
        return link
    }

    /// The extensions AudioToolbox gives the format the bytes turned out to be
    /// in, or nil when it doesn't recognise them.
    static func detectedExtensions(of url: URL) -> [String]? {
        guard let reader = try? Reader(url) else { return nil }
        return withExtendedLifetime(reader) {
            var fileID: AudioFileID?
            let status = AudioFileOpenWithCallbacks(
                Unmanaged.passUnretained(reader).toOpaque(),
                { context, position, count, buffer, actual in
                    Unmanaged<Reader>.fromOpaque(context).takeUnretainedValue()
                        .read(at: position, count: count, into: buffer, actual: actual)
                },
                nil,
                { context in
                    Unmanaged<Reader>.fromOpaque(context).takeUnretainedValue().size
                },
                nil,
                // No hint: being told the name is exactly what went wrong.
                0,
                &fileID
            )
            guard status == noErr, let fileID else { return nil }
            defer { AudioFileClose(fileID) }

            var type: AudioFileTypeID = 0
            var typeSize = UInt32(MemoryLayout<AudioFileTypeID>.size)
            guard AudioFileGetProperty(fileID, kAudioFilePropertyFileFormat, &typeSize, &type) == noErr
            else { return nil }

            var extensions: Unmanaged<CFArray>?
            var extensionsSize = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
            guard AudioFileGetGlobalInfo(
                kAudioFileGlobalInfo_ExtensionsForType,
                UInt32(MemoryLayout<AudioFileTypeID>.size),
                &type,
                &extensionsSize,
                &extensions
            ) == noErr,
                  let list = extensions?.takeRetainedValue() as? [String],
                  !list.isEmpty
            else { return nil }
            return list.map { $0.lowercased() }
        }
    }

    // MARK: - Links

    /// Not prefixed `Konfer-` like the pipeline's scratch files: those are
    /// one run's and deleted after it, and the tests count them.
    private static var directory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Konfer Renamed Recordings", isDirectory: true)
    }

    /// One link per source file, made once and then reused.
    ///
    /// Stable rather than made per use, because the player, the waveform and
    /// a transcription may all hold the same recording open at once and none
    /// of them should delete it from under the others. A link costs nothing,
    /// and the system clears the temporary directory itself. It keeps the
    /// recording's own name, inside a folder named after its path, so that an
    /// error naming the link still names the user's file.
    private static func link(to url: URL, extension pathExtension: String) throws -> URL {
        let source = url.standardizedFileURL.path
        let folder = directory.appendingPathComponent(
            SHA256.hash(data: Data(source.utf8)).prefix(8)
                .map { String(format: "%02x", $0) }
                .joined(),
            isDirectory: true
        )
        let link = folder
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(pathExtension)

        let manager = FileManager.default
        if let existing = try? manager.destinationOfSymbolicLink(atPath: link.path) {
            if existing == source { return link }
            try manager.removeItem(at: link)
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        // Another caller may make the same link between the check and here,
        // which is just as good — so the outcome is checked, not the call.
        try? manager.createSymbolicLink(atPath: link.path, withDestinationPath: source)
        guard (try? manager.destinationOfSymbolicLink(atPath: link.path)) == source else {
            throw CocoaError(.fileWriteUnknown)
        }
        return link
    }
}

/// Feeds AudioToolbox the file on demand, for as much of it as it asks for —
/// identifying an MP4 can mean reading its index from the end, the rest only
/// read a header.
nonisolated private final class Reader {

    let handle: FileHandle
    let size: Int64

    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = Int64(try handle.seekToEnd())
    }

    deinit { try? handle.close() }

    func read(
        at position: Int64,
        count: UInt32,
        into buffer: UnsafeMutableRawPointer,
        actual: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        do {
            try handle.seek(toOffset: UInt64(position))
            let data = try handle.read(upToCount: Int(count)) ?? Data()
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
            actual.pointee = UInt32(data.count)
            return noErr
        } catch {
            actual.pointee = 0
            return kAudioFileUnspecifiedError
        }
    }
}
