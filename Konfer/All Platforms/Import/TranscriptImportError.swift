//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Failures importing a transcript another app produced.
///
/// Kept apart from ``PipelineError``: an import runs no models, touches no
/// audio and cannot be cancelled, so none of that vocabulary applies and
/// sharing the type would only invite a case from one to surface in the other.
nonisolated enum TranscriptImportError: LocalizedError {

    case unreadable(URL, underlying: Error)
    case unrecognizedFormat(URL)
    case noSpeech(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url, _):
            "Couldn't read \(url.lastPathComponent)."
        case .unrecognizedFormat(let url):
            "\(url.lastPathComponent) isn't a transcript Konfer can import."
        case .noSpeech(let url):
            "\(url.lastPathComponent) contains no speech."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unreadable:
            "The file may have moved, or may not be readable."
        case .unrecognizedFormat:
            "Konfer imports the JSON transcripts the Klang app exports. To "
            + "transcribe a recording instead, drop the audio or video file."
        case .noSpeech:
            "Every line in the file is empty."
        }
    }

    /// The underlying error, for the detail line in an error alert.
    var underlyingDescription: String? {
        switch self {
        case .unreadable(_, let error): error.localizedDescription
        default: nil
        }
    }
}
