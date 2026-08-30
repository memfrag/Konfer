//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Failures the transcription pipeline surfaces to the UI.
nonisolated enum PipelineError: LocalizedError {

    case modelsNotLoaded
    case modelDownloadFailed(underlying: Error)
    case audioUnreadable(URL, underlying: Error)
    case noAudioTrack(URL)
    case transcriptionFailed(underlying: Error)
    case appleSpeechUnavailable
    case languageUnsupported(MeetingLanguage)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelsNotLoaded:
            "The speech recognition models are not loaded."
        case .modelDownloadFailed:
            "Couldn't download the speech models."
        case .audioUnreadable(let url, _):
            "Couldn't read \(url.lastPathComponent)."
        case .noAudioTrack(let url):
            "\(url.lastPathComponent) has no audio track."
        case .transcriptionFailed:
            "Transcription failed."
        case .appleSpeechUnavailable:
            "Apple's speech recognition isn't available on this Mac."
        case .languageUnsupported(let language):
            "Apple's speech recognition doesn't support \(language.displayName)."
        case .cancelled:
            "Transcription was cancelled."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelDownloadFailed:
            "Snoopy needs an internet connection once, to download its speech "
            + "models. After that it works entirely offline. Check your "
            + "connection and try again."
        case .audioUnreadable:
            "The file may be in an unsupported format, or may have moved."
        case .noAudioTrack:
            "Choose a file that contains audio."
        case .appleSpeechUnavailable:
            "Choose KB-Whisper in Settings ▸ Transcription instead."
        case .languageUnsupported:
            "Apple covers 30 locales, and Swedish isn't one of them. "
            + "Choose KB-Whisper in Settings ▸ Transcription for this recording."
        default:
            nil
        }
    }

    /// The underlying error, for the detail line in an error banner.
    var underlyingDescription: String? {
        switch self {
        case .modelDownloadFailed(let error),
             .audioUnreadable(_, let error),
             .transcriptionFailed(let error):
            error.localizedDescription
        default:
            nil
        }
    }
}
