//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The library is a directory of real folders that the user can also
/// rearrange in Finder, and every library written before folders existed has
/// to open in it unchanged. These run against a scratch directory, reading it
/// back with a second store wherever what matters is what is on disk.
@MainActor
struct MeetingStoreTests {

    // MARK: - Fixtures

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func meeting(_ title: String, id: UUID = UUID(), importedAt: Date = Date()) -> Meeting {
        Meeting(
            id: id,
            title: title,
            audioPath: "/tmp/\(title).m4a",
            duration: 60,
            importedAt: importedAt,
            language: .swedish,
            speakers: [],
            utterances: []
        )
    }

    /// Writes a meeting the way the store used to: by id, at the top level.
    private func writeLegacy(_ meeting: Meeting, in folder: String? = nil) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var target = directory
        if let folder {
            target = target.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        }
        let url = target.appendingPathComponent("\(meeting.id.uuidString).json")
        try encoder.encode(meeting).write(to: url)
        return url
    }

    private func files(in folder: String? = nil) throws -> Set<String> {
        let url = folder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory
        return Set(try FileManager.default.contentsOfDirectory(atPath: url.path).filter { !$0.hasPrefix(".") })
    }

    // MARK: - Existing libraries

    @Test("A library written before folders opens with every meeting, now named after its title")
    func legacyLibraryOpens() throws {
        let kickoff = meeting("Kickoff")
        let sync = meeting("Sync meeting")
        _ = try writeLegacy(kickoff)
        _ = try writeLegacy(sync)

        let store = MeetingStore(directory: directory)

        #expect(Set(store.meetings.map(\.id)) == [kickoff.id, sync.id])
        #expect(store.folder(of: kickoff.id) == .root)
        #expect(try files() == ["Kickoff.json", "Sync meeting.json"])
        #expect(MeetingStore(directory: directory).meetings.count == 2)
    }

    @Test("Two meetings with the same title get numbered files rather than one overwriting the other")
    func sameTitlesAreNumbered() throws {
        _ = try writeLegacy(meeting("Standup"))
        _ = try writeLegacy(meeting("Standup"))

        let store = MeetingStore(directory: directory)

        #expect(store.meetings.count == 2)
        #expect(try files() == ["Standup.json", "Standup 2.json"])
    }

    @Test("A file the user renamed in Finder keeps its name")
    func finderNamesAreKept() throws {
        let kickoff = meeting("Kickoff")
        let legacy = try writeLegacy(kickoff)
        try FileManager.default.moveItem(at: legacy, to: directory.appendingPathComponent("Acme kickoff.json"))

        let store = MeetingStore(directory: directory)
        store.modify(kickoff.id) { $0.keepEverything() }

        #expect(try files() == ["Acme kickoff.json"])
    }

    // MARK: - Never overwriting

    @Test("A new meeting never overwrites a file the library couldn't read")
    func unreadableFilesAreNeverOverwritten() throws {
        let stranger = directory.appendingPathComponent("Kickoff.json")
        try Data("not a transcript".utf8).write(to: stranger)

        let store = MeetingStore(directory: directory)
        store.add(meeting("Kickoff"))

        #expect(try String(contentsOf: stranger, encoding: .utf8) == "not a transcript")
        #expect(try files() == ["Kickoff.json", "Kickoff 2.json"])
    }

    @Test("A meeting that can't be decoded is skipped, and left untouched by writes to the others")
    func undecodableMeetingSurvivesWrites() throws {
        let brokenURL = directory.appendingPathComponent("\(UUID().uuidString).json")
        let broken = Data(#"{"title" : "Truncated", "utterances" : ["#.utf8)
        try broken.write(to: brokenURL)

        let store = MeetingStore(directory: directory)
        #expect(store.meetings.isEmpty)

        let standup = meeting("Standup")
        store.add(standup)
        store.modify(standup.id) { $0.title = "Standup, renamed" }
        store.add(meeting("Retro"))
        store.delete(standup.id)

        #expect(try Data(contentsOf: brokenURL) == broken)
        #expect(MeetingStore(directory: directory).meetings.map(\.title) == ["Retro"])
    }

    @Test("Names that differ only in case clash, as they do on the disk")
    func caseInsensitiveClashes() throws {
        let store = MeetingStore(directory: directory)
        store.add(meeting("Kickoff"))
        store.add(meeting("kickoff"))

        #expect(try files().count == 2)
        #expect(MeetingStore(directory: directory).meetings.count == 2)
    }

    @Test("Changing only the case of a title renames the file rather than losing it")
    func caseOnlyRename() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("kickoff")
        store.add(kickoff)

        store.modify(kickoff.id) { $0.rename(to: "Kickoff") }

        #expect(try files() == ["Kickoff.json"])
        #expect(MeetingStore(directory: directory).meeting(kickoff.id)?.title == "Kickoff")
    }

    // MARK: - Filenames

    @Test("A title that would make a hidden or nested file still makes a visible one")
    func unsafeTitlesAreMadeSafe() throws {
        let store = MeetingStore(directory: directory)
        let dotted = meeting("...notes")
        let slashed = meeting("Q3/Q4 review: budget")
        let blank = meeting("   ")
        store.add(dotted)
        store.add(slashed)
        store.add(blank)

        #expect(try files() == ["notes.json", "Q3-Q4 review- budget.json", "Untitled.json"])
        #expect(MeetingStore(directory: directory).meetings.count == 3)
    }

    @Test("A very long title is shortened to a name the disk accepts")
    func longTitlesAreShortened() throws {
        let store = MeetingStore(directory: directory)
        let long = meeting(String(repeating: "Långt möte ", count: 60))
        store.add(long)

        let name = try #require(try files().first)
        #expect(name.utf8.count <= 255)
        #expect(MeetingStore(directory: directory).meeting(long.id) != nil)
    }

    // MARK: - Renaming

    @Test("Renaming a meeting renames its file, and it is read back once")
    func renamingRenamesTheFile() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")
        store.add(kickoff)

        store.modify(kickoff.id) { $0.rename(to: "Acme kickoff") }

        #expect(try files() == ["Acme kickoff.json"])
        let reread = MeetingStore(directory: directory)
        #expect(reread.meetings.map(\.title) == ["Acme kickoff"])
    }

    @Test("Saving a meeting without changing its title leaves the filename alone")
    func savingKeepsTheName() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")
        store.add(kickoff)
        store.add(meeting("Kickoff"))

        store.modify(kickoff.id) { $0.keepEverything() }

        #expect(try files() == ["Kickoff.json", "Kickoff 2.json"])
    }

    // MARK: - Duplicates

    @Test("Two files for one meeting read as one: the newer")
    func duplicatesReadAsTheNewer() throws {
        let kickoff = meeting("Kickoff")
        let older = try writeLegacy(kickoff)
        let renamed = directory.appendingPathComponent("Kickoff.json")
        try FileManager.default.moveItem(at: older, to: renamed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -3600)],
            ofItemAtPath: renamed.path
        )

        // What an older Konfer does: edits are written back by id.
        var edited = kickoff
        edited.title = "Kickoff, edited"
        _ = try writeLegacy(edited)

        let store = MeetingStore(directory: directory)

        #expect(store.meetings.count == 1)
        #expect(store.meetings.first?.title == "Kickoff, edited")
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    // MARK: - Folders

    @Test("Meetings in folders load where they are, and empty folders are listed")
    func foldersLoad() throws {
        let acme = meeting("Acme kickoff")
        _ = try writeLegacy(acme, in: "Clients/Acme")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Archive", isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = MeetingStore(directory: directory)

        #expect(store.folder(of: acme.id) == MeetingFolder(["Clients", "Acme"]))
        #expect(store.folders == [
            MeetingFolder(["Archive"]),
            MeetingFolder(["Clients"]),
            MeetingFolder(["Clients", "Acme"])
        ])
    }

    @Test("A meeting moved into a folder is there when the library is read again")
    func movingAMeeting() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")
        store.add(kickoff)
        let clients = try #require(store.createFolder(named: "Clients"))

        store.move(kickoff.id, to: clients)

        #expect(try files(in: "Clients") == ["Kickoff.json"])
        #expect(MeetingStore(directory: directory).folder(of: kickoff.id) == clients)
    }

    @Test("A new meeting meant for a folder that has gone lands at the top level")
    func missingFolderFallsBackToTheTop() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")

        store.add(kickoff, in: MeetingFolder(["Deleted meanwhile"]))

        #expect(store.folder(of: kickoff.id) == .root)
        #expect(try files() == ["Kickoff.json"])
    }

    @Test("Renaming a folder takes its meetings and subfolders with it")
    func renamingAFolder() throws {
        let store = MeetingStore(directory: directory)
        let clients = try #require(store.createFolder(named: "Clients"))
        let acme = try #require(store.createFolder(named: "Acme", in: clients))
        let kickoff = meeting("Kickoff")
        store.add(kickoff, in: acme)

        let customers = try #require(store.renameFolder(clients, to: "Customers"))

        #expect(customers == MeetingFolder(["Customers"]))
        #expect(store.folder(of: kickoff.id) == MeetingFolder(["Customers", "Acme"]))
        #expect(store.folders == [customers, MeetingFolder(["Customers", "Acme"])])
        #expect(MeetingStore(directory: directory).folder(of: kickoff.id) == MeetingFolder(["Customers", "Acme"]))
    }

    @Test("A folder can't be moved into itself or anything inside it")
    func noFolderInsideItself() throws {
        let store = MeetingStore(directory: directory)
        let clients = try #require(store.createFolder(named: "Clients"))
        let acme = try #require(store.createFolder(named: "Acme", in: clients))

        #expect(store.moveFolder(clients, into: clients) == nil)
        #expect(store.moveFolder(clients, into: acme) == nil)
        #expect(store.folders == [clients, acme])
    }

    @Test("Deleting a folder moves what was in it up a level, numbering what clashes")
    func deletingAFolderKeepsItsContents() throws {
        let store = MeetingStore(directory: directory)
        let clients = try #require(store.createFolder(named: "Clients"))
        let acme = try #require(store.createFolder(named: "Acme", in: clients))
        let inside = meeting("Kickoff")
        let outside = meeting("Kickoff")
        let nested = meeting("Acme sync")
        store.add(outside)
        store.add(inside, in: clients)
        store.add(nested, in: acme)

        store.deleteFolder(clients)

        #expect(store.folders == [MeetingFolder(["Acme"])])
        #expect(store.folder(of: inside.id) == .root)
        #expect(store.folder(of: nested.id) == MeetingFolder(["Acme"]))
        #expect(try files() == ["Acme", "Kickoff.json", "Kickoff 2.json"])

        let reread = MeetingStore(directory: directory)
        #expect(reread.meetings.count == 3)
        #expect(reread.folder(of: nested.id) == MeetingFolder(["Acme"]))
    }

    // MARK: - Reading again

    @Test("Reading the library again finds a meeting filed in Finder meanwhile")
    func reloadFollowsFinder() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")
        store.add(kickoff)
        let archive = directory.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: directory.appendingPathComponent("Kickoff.json"),
            to: archive.appendingPathComponent("Kickoff.json")
        )

        store.reload()

        #expect(store.folders == [MeetingFolder(["Archive"])])
        #expect(store.folder(of: kickoff.id) == MeetingFolder(["Archive"]))
    }

    @Test("Reading the library again picks up a transcript changed outside Konfer")
    func reloadRereadsChangedFiles() throws {
        let store = MeetingStore(directory: directory)
        let kickoff = meeting("Kickoff")
        store.add(kickoff)

        var edited = kickoff
        edited.title = "Kickoff, edited elsewhere"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = directory.appendingPathComponent("Kickoff.json")
        try encoder.encode(edited).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 60)],
            ofItemAtPath: file.path
        )

        store.reload()

        #expect(store.meeting(kickoff.id)?.title == "Kickoff, edited elsewhere")
    }

    @Test("Deleting a meeting removes its file wherever it is filed")
    func deletingAFiledMeeting() throws {
        let store = MeetingStore(directory: directory)
        let clients = try #require(store.createFolder(named: "Clients"))
        let kickoff = meeting("Kickoff")
        store.add(kickoff, in: clients)

        store.delete(kickoff.id)

        #expect(try files(in: "Clients").isEmpty)
        #expect(MeetingStore(directory: directory).meetings.isEmpty)
    }
}
