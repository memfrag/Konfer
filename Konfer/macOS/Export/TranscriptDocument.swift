//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

/// A rendered transcript, ready for `fileExporter`.
struct TranscriptDocument: FileDocument {

    /// SubRip has no system type — `UTType(filenameExtension: "srt")` resolves
    /// only to a dynamic one, which a save panel will not accept — so Konfer
    /// declares it in `Info.plist` as an imported type. WebVTT needs no such
    /// help: macOS already knows `org.w3.webvtt`.
    static let webVTT = UTType("org.w3.webvtt") ?? .plainText
    static let subRip = UTType(importedAs: "org.subrip.srt", conformingTo: .plainText)

    static let readableContentTypes: [UTType] = [.plainText, .json, webVTT, subRip]

    let data: Data
    let contentType: UTType

    init(meeting: Meeting, format: TranscriptExporter.Format) throws {
        data = try TranscriptExporter.data(for: meeting, format: format)
        contentType = switch format {
        case .markdown: .plainText
        case .json: .json
        case .webVTT: Self.webVTT
        case .subRip: Self.subRip
        }
    }

    init(configuration: ReadConfiguration) throws {
        // Konfer reads a transcript back only through the Klang importer, which
        // has its own path and its own type. Nothing here is readable: these
        // are renderings of a meeting, and several of them throw away more than
        // they keep.
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
