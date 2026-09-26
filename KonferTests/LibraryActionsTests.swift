//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import Testing
import Foundation
@testable import Konfer

/// The sidebar's Finder, terminal and copy actions. Opening a terminal or a
/// Finder window is left to a person; what can go wrong quietly is the path
/// they are handed, and that is what these check.
@MainActor
struct LibraryActionsTests {

    private let store: MeetingStore
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryActionsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = MeetingStore(directory: directory)
    }

    private func meeting(_ title: String) -> Meeting {
        Meeting(
            id: UUID(),
            title: title,
            audioPath: "/tmp/\(title).m4a",
            duration: 60,
            importedAt: Date(),
            language: .english,
            speakers: [],
            utterances: []
        )
    }

    @Test("A filed meeting's transcript and folder paths are what is on disk")
    func pathsPointAtTheDisk() throws {
        let clients = try #require(store.createFolder(named: "Acme Clients"))
        let kickoff = meeting("Kickoff call")
        store.add(kickoff, in: clients)

        let transcript = try #require(store.fileURL(of: kickoff.id))
        let folder = store.url(of: try #require(store.folder(of: kickoff.id)))

        #expect(FileManager.default.fileExists(atPath: transcript.path))
        #expect(transcript.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(transcript.lastPathComponent == "Kickoff call.json")
    }

    @Test("A path is copied as plain, unquoted text, spaces and all")
    func copiesThePlainPath() throws {
        let kickoff = meeting("Kickoff call")
        store.add(kickoff)
        let transcript = try #require(store.fileURL(of: kickoff.id))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("LibraryActionsTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        LibraryActions.copyPath(of: transcript, to: pasteboard)

        #expect(pasteboard.string(forType: .string) == transcript.path)
        #expect(pasteboard.string(forType: .string)?.hasSuffix("/Kickoff call.json") == true)
    }

    @Test("There is always a terminal to open, and a name to call it by")
    func findsATerminal() throws {
        let terminal = try #require(LibraryActions.terminalApplication)

        #expect(terminal.pathExtension == "app")
        #expect(!LibraryActions.terminalName.isEmpty)
        #expect(!LibraryActions.terminalName.hasSuffix(".app"))
    }
}
