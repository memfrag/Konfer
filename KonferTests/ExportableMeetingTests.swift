//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// `ExportableMeeting` is how the transcript pane offers itself to the menu
/// bar, and SwiftUI republishes a focused value only when it compares unequal.
/// So its `==` is not a formality: anything the menu reads and this ignores is
/// a menu item that silently stops keeping up.
@MainActor
struct ExportableMeetingTests {

    private func make(
        id: UUID,
        canExportVideo: Bool = false,
        translationTarget: MeetingLanguage? = nil
    ) -> ExportableMeeting {
        ExportableMeeting(
            id: id,
            export: { _, _ in },
            exportVideo: { _ in },
            canExportVideo: canExportVideo,
            translationTarget: translationTarget
        )
    }

    @Test("A meeting that has just been translated is not the meeting it was")
    func translationTargetIsCompared() {
        let id = UUID()

        #expect(make(id: id) != make(id: id, translationTarget: .english))
    }

    @Test("Translating into a different language is a change too")
    func differentTargetsDiffer() {
        let id = UUID()

        #expect(
            make(id: id, translationTarget: .english)
                != make(id: id, translationTarget: .german)
        )
    }

    @Test("A recording that turns out to have a picture is not the meeting it was")
    func canExportVideoIsCompared() {
        let id = UUID()

        #expect(make(id: id) != make(id: id, canExportVideo: true))
    }

    @Test("Two different meetings are never the same")
    func differentMeetings() {
        #expect(make(id: UUID()) != make(id: UUID()))
    }

    @Test("Nothing changing compares equal, so the menu isn't rebuilt for nothing")
    func unchangedIsEqual() {
        let id = UUID()

        #expect(
            make(id: id, canExportVideo: true, translationTarget: .english)
                == make(id: id, canExportVideo: true, translationTarget: .english)
        )
    }
}
