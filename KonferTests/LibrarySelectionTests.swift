//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Where a new meeting's folder picker starts. Every sheet that makes a
/// meeting asks this, including the one the Recorder window opens, so it is
/// the one place the Settings choice is applied.
@MainActor
struct LibrarySelectionTests {

    private let store: MeetingStore
    private let clients: MeetingFolder

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibrarySelectionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = MeetingStore(directory: directory)
        clients = try #require(store.createFolder(named: "Clients"))
    }

    @Test("By default a new meeting starts in the folder selected in the sidebar")
    func defaultsToTheSelectedFolder() {
        let selection = LibrarySelection()
        selection.folder = clients

        #expect(selection.folderForNewMeeting(settings: .mock(), in: store) == clients)
    }

    @Test("Set to the top level, a new meeting starts there whatever is selected")
    func topLevelSettingWins() {
        let settings = AppSettings.mock()
        settings.newMeetingFolder = .topLevel
        let selection = LibrarySelection()
        selection.folder = clients

        #expect(selection.folderForNewMeeting(settings: settings, in: store) == .root)
    }

    @Test("A selected folder that has since gone starts the picker at the top level")
    func vanishedFolderFallsBack() {
        let selection = LibrarySelection()
        selection.folder = clients
        store.deleteFolder(clients)

        #expect(selection.folderForNewMeeting(settings: .mock(), in: store) == .root)
    }
}
