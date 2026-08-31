//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

/// A rendered transcript, ready for `fileExporter`.
struct TranscriptDocument: FileDocument {

    static let readableContentTypes: [UTType] = [.plainText, .json]

    let data: Data
    let contentType: UTType

    init(meeting: Meeting, format: TranscriptExporter.Format) throws {
        data = try TranscriptExporter.data(for: meeting, format: format)
        contentType = switch format {
        case .markdown: .plainText
        case .json: .json
        }
    }

    init(configuration: ReadConfiguration) throws {
        // Konfer exports transcripts but never reads them back — a transcript
        // is derived from audio, and importing one would produce a meeting with
        // no recording behind it.
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
