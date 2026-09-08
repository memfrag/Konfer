//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The sidebar and the transcript pane both save transcripts, by different
/// routes — a panel from a list, a sheet from a document window. The naming
/// rule is the part they must agree on, so the same meeting saved from either
/// place cannot land under two different names.
@MainActor
struct MeetingExportTests {

    private func makeMeeting(translatedInto target: MeetingLanguage? = nil) -> Meeting {
        var meeting = Meeting(
            id: UUID(),
            title: "Kickoff",
            audioPath: "/tmp/kickoff.m4a",
            duration: 60,
            importedAt: Date(),
            language: .swedish,
            speakers: [],
            utterances: []
        )
        if let target {
            meeting.translation = TranscriptTranslation(target: target)
        }
        return meeting
    }

    @Test("An exported transcript is named after the meeting")
    func namesAfterTheMeeting() {
        #expect(
            MeetingExport.filename(
                for: makeMeeting(), format: .markdown, rendering: .original
            ) == "Kickoff.md"
        )
        #expect(
            MeetingExport.filename(
                for: makeMeeting(), format: .subRip, rendering: .original
            ) == "Kickoff.srt"
        )
    }

    @Test("A translated export carries its language, so the two don't overwrite each other")
    func namesTheLanguage() {
        let meeting = makeMeeting(translatedInto: .english)

        #expect(
            MeetingExport.filename(for: meeting, format: .markdown, rendering: .translated)
                == "Kickoff (English).md"
        )
        #expect(
            MeetingExport.filename(for: meeting, format: .markdown, rendering: .original)
                == "Kickoff.md"
        )
    }

    @Test("Asking for a translated name from an untranslated meeting falls back to the plain one")
    func fallsBackWithoutATranslation() {
        #expect(
            MeetingExport.filename(
                for: makeMeeting(), format: .webVTT, rendering: .translated
            ) == "Kickoff.vtt"
        )
    }

    @Test("Every format saves under the extension it declares")
    func extensionsMatch() {
        for format in TranscriptExporter.Format.allCases {
            let name = MeetingExport.filename(
                for: makeMeeting(), format: format, rendering: .original
            )
            #expect(name.hasSuffix(".\(format.fileExtension)"))
        }
    }

    @Test("Each format saves as a type the save panel can offer")
    func contentTypesAreDistinct() {
        let types = TranscriptExporter.Format.allCases.map(MeetingExport.contentType(for:))

        #expect(Set(types).count == TranscriptExporter.Format.allCases.count)
        #expect(MeetingExport.contentType(for: .json) == .json)
    }
}
