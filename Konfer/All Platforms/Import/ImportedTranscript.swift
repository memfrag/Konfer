//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A transcript file dropped on Konfer, in whichever format it turned out to be.
///
/// Told apart by content rather than by name: both are `.json`, and a file's
/// name says nothing about which app wrote it.
nonisolated enum ImportedTranscript: Sendable {

    /// Konfer's own JSON export, coming back.
    case konfer(KonferTranscript)

    /// A transcript the Klang app exported.
    case klang(KlangTranscript)

    /// Reads the file and decodes it as the first format that fits.
    ///
    /// Konfer's is tried first because it is the stricter of the two: it
    /// requires a title, a language and a roster that a Klang file never has,
    /// whereas a Klang file is little more than one array.
    static func read(contentsOf url: URL) throws -> ImportedTranscript {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TranscriptImportError.unreadable(url, underlying: error)
        }
        if let konfer = try KonferTranscript.decode(data, from: url) {
            return .konfer(konfer)
        }
        return .klang(try KlangTranscript.decode(data, from: url))
    }

    var speakerCount: Int {
        switch self {
        case .konfer(let transcript): transcript.speakerCount
        case .klang(let transcript): transcript.speakerIDs.count
        }
    }

    /// The recording's length for a Konfer export; for Klang, where the last
    /// person stopped talking, which is all its file says.
    var duration: TimeInterval {
        switch self {
        case .konfer(let transcript): transcript.duration
        case .klang(let transcript): transcript.duration
        }
    }

    /// The language the file itself declares. Klang's doesn't, so the import
    /// sheet has to ask; Konfer's does, and asking would only invite filing it
    /// under the wrong one.
    var declaredLanguage: MeetingLanguage? {
        switch self {
        case .konfer(let transcript): transcript.language
        case .klang: nil
        }
    }

    /// Assembles the meeting.
    ///
    /// `language` is what the import sheet settled on — for a Konfer export,
    /// the one it declared, since the sheet doesn't offer to change it. The
    /// title is the one the meeting had when there is one, and the file's
    /// name otherwise, exactly as a recording's is.
    func meeting(from url: URL, language: MeetingLanguage) -> Meeting {
        switch self {
        case .konfer(let transcript):
            transcript.meeting()
        case .klang(let transcript):
            transcript.meeting(title: url.deletingPathExtension().lastPathComponent, language: language)
        }
    }
}
