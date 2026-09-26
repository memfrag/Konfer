//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation
import OSLog

/// The meeting library: one JSON file per meeting, named after its title, in
/// real folders under `Meetings/`.
///
/// Every mutation writes through immediately. Meetings are small enough
/// (a few hundred KB for an hour) that batching saves would add risk without
/// buying anything.
///
/// **Where a meeting is filed is the disk's business, not the meeting's.** A
/// meeting's folder is wherever its file is, so nothing about it is stored in
/// the transcript: moving files in Finder files them, and every transcript
/// written before folders existed decodes exactly as it did, at the top level.
///
/// Files were once named by meeting id. Reading the library renames those
/// after their titles, one move each; any that fails keeps its id-name and
/// loads regardless.
///
@Observable @MainActor
final class MeetingStore {

    private(set) var meetings: [Meeting] = []

    /// Every folder in the library, empty ones included, parents before their
    /// children. The top level isn't listed.
    private(set) var folders: [MeetingFolder] = []

    /// Where each meeting's file is.
    private var locations: [UUID: Location] = [:]

    /// What each file held when it was last read or written, and when it
    /// was modified then — so reading the library again decodes only what
    /// changed. The app reads it again every time it comes to the front, and
    /// an hour's transcript is over a megabyte of JSON.
    @ObservationIgnored
    private var lastSeen: [Location: (meeting: Meeting, modified: Date)] = [:]

    @ObservationIgnored
    private let directory: URL

    private static let logger = Logger(subsystem: "pizza.martin.Konfer", category: "Library")

    init(directory: URL = LibraryLocation.meetingsDirectory) {
        self.directory = directory
        load()
    }

    // MARK: - Access

    func meeting(_ id: UUID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    /// Meetings already transcribed from this file, so an accidental re-drop
    /// can be flagged rather than silently duplicated.
    func existingMeetings(forAudioAt path: String) -> [Meeting] {
        meetings.filter { $0.audioPath == path }
    }

    /// The folder a meeting is filed in.
    func folder(of id: UUID) -> MeetingFolder? {
        locations[id]?.folder
    }

    /// The transcript file itself.
    func fileURL(of id: UUID) -> URL? {
        locations[id].map(url(of:))
    }

    /// Where a folder is on disk.
    func url(of folder: MeetingFolder) -> URL {
        folder.url(in: directory)
    }

    /// The meetings filed directly in a folder, newest first.
    func meetings(in folder: MeetingFolder) -> [Meeting] {
        meetings.filter { locations[$0.id]?.folder == folder }
    }

    /// The folders directly inside a folder, in Finder's order.
    func subfolders(of folder: MeetingFolder) -> [MeetingFolder] {
        folders.filter { $0.parent == folder }
    }

    /// How many meetings are in a folder, counting every folder inside it.
    func meetingCount(in folder: MeetingFolder) -> Int {
        locations.values.count { folder.contains($0.folder) }
    }

    // MARK: - Mutation

    /// Files a new meeting.
    ///
    /// Into the top level when `folder` has gone — a transcription takes
    /// minutes, and the folder it was meant for can be renamed or deleted in
    /// the meantime. A finished transcript is worth more than its filing.
    func add(_ meeting: Meeting, in folder: MeetingFolder = .root) {
        let folder = exists(folder) ? folder : .root
        let file = LibraryName.available(
            filename(for: meeting),
            extension: "json",
            in: url(of: folder)
        )
        meetings.insert(meeting, at: 0)
        locations[meeting.id] = Location(folder: folder, filename: file.lastPathComponent)
        write(meeting)
    }

    func update(_ meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        let previousTitle = meetings[index].title
        meetings[index] = meeting
        save(meeting, previousTitle: previousTitle)
    }

    /// Applies an edit to the meeting with the given id and persists the result.
    func modify(_ id: UUID, _ transform: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        let previousTitle = meetings[index].title
        transform(&meetings[index])
        save(meetings[index], previousTitle: previousTitle)
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        if let location = locations.removeValue(forKey: id) {
            try? FileManager.default.removeItem(at: url(of: location))
        }
        WaveformStore.removeCache(for: id)
    }

    /// Refiles a meeting, keeping its filename unless the new folder already
    /// has one like it.
    ///
    /// The name it keeps may be one the user gave it in Finder, which is
    /// theirs to keep.
    func move(_ id: UUID, to folder: MeetingFolder) {
        guard let location = locations[id], location.folder != folder, exists(folder) else { return }
        let source = url(of: location)
        let destination = LibraryName.available(
            source.deletingPathExtension().lastPathComponent,
            extension: "json",
            in: url(of: folder)
        )
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            locations[id] = Location(folder: folder, filename: destination.lastPathComponent)
        } catch {
            Self.logger.error("Could not move a meeting: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Folders

    /// Makes a folder, numbered if the name is taken, and returns it.
    @discardableResult
    func createFolder(named name: String = "New Folder", in parent: MeetingFolder = .root) -> MeetingFolder? {
        guard exists(parent) else { return nil }
        let target = LibraryName.available(
            LibraryName.sanitized(name, fallback: "New Folder"),
            in: url(of: parent)
        )
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            Self.logger.error("Could not create a folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let folder = parent.appending(target.lastPathComponent)
        folders.append(folder)
        folders.sort()
        return folder
    }

    /// Renames a folder and returns it as it is now called.
    @discardableResult
    func renameFolder(_ folder: MeetingFolder, to name: String) -> MeetingFolder? {
        guard let parent = folder.parent else { return nil }
        return relocate(folder, into: parent, named: LibraryName.sanitized(name, fallback: folder.name))
    }

    /// Moves a folder, with everything in it, into another.
    ///
    /// Refused into itself or anything inside it, which would have the folder
    /// contain itself.
    @discardableResult
    func moveFolder(_ folder: MeetingFolder, into parent: MeetingFolder) -> MeetingFolder? {
        guard !folder.contains(parent), folder.parent != parent else { return nil }
        return relocate(folder, into: parent, named: folder.name)
    }

    /// Removes a folder, moving what was in it up one level.
    ///
    /// Nothing is deleted with it: the meetings and subfolders take its place,
    /// numbered where the level above already has something of the same name.
    /// The folder itself goes only once it holds nothing visible, so anything
    /// that could not be moved is still where it was.
    func deleteFolder(_ folder: MeetingFolder) {
        guard let parent = folder.parent else { return }
        let fileManager = FileManager.default
        let source = url(of: folder)
        let destination = url(of: parent)

        let items = (try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for item in items {
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let target = isFolder
                ? LibraryName.available(item.lastPathComponent, in: destination)
                : LibraryName.available(
                    item.deletingPathExtension().lastPathComponent,
                    extension: item.pathExtension,
                    in: destination
                )
            do {
                try fileManager.moveItem(at: item, to: target)
            } catch {
                Self.logger.error("Could not move out of a folder: \(error.localizedDescription, privacy: .public)")
                continue
            }
            if isFolder {
                rebase(folder.appending(item.lastPathComponent), to: parent.appending(target.lastPathComponent))
            } else if let id = locations.first(where: {
                $0.value.folder == folder && $0.value.filename == item.lastPathComponent
            })?.key {
                locations[id] = Location(folder: parent, filename: target.lastPathComponent)
            }
        }

        let leftovers = (try? fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard leftovers.isEmpty else { return }
        try? fileManager.removeItem(at: source)
        folders.removeAll { $0 == folder }
    }

    // MARK: - Reading the disk

    /// Reads the library again, for when it may have changed under the app —
    /// someone filing meetings in Finder.
    func reload() {
        load()
    }

    /// Reads every meeting, skipping the files it can't.
    ///
    /// Skipping is safe here where it is not for the People roster, because
    /// nothing is ever written back over a file this passes by: only meetings
    /// that loaded (or were just created) are ever written, moved or deleted,
    /// each at the file it was read from, and a new or renamed file's name is
    /// chosen by asking the disk what is free — so a skipped file's name counts
    /// as taken. A file that fails to decode stays on disk untouched, invisible
    /// until whatever broke it is fixed.
    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var found: [UUID: (meeting: Meeting, location: Location, modified: Date)] = [:]
        var foundFolders: [MeetingFolder] = []

        func scan(_ folder: MeetingFolder) {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: url(of: folder),
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for item in items {
                let values = try? item.resourceValues(
                    forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey]
                )
                if values?.isDirectory == true {
                    // A bundle is a file to the user, whatever it is on disk.
                    guard values?.isPackage != true else { continue }
                    let child = folder.appending(item.lastPathComponent)
                    foundFolders.append(child)
                    scan(child)
                    continue
                }
                guard item.pathExtension == "json" else { continue }
                let location = Location(folder: folder, filename: item.lastPathComponent)
                let modified = values?.contentModificationDate ?? .distantPast

                let meeting: Meeting
                if let seen = lastSeen[location], seen.modified == modified {
                    meeting = seen.meeting
                } else {
                    guard let data = try? Data(contentsOf: item),
                          let decoded = try? decoder.decode(Meeting.self, from: data),
                          // Written by a newer version of the app: skip rather
                          // than crash or silently mangle.
                          decoded.schemaVersion <= Meeting.currentSchemaVersion
                    else { continue }
                    meeting = decoded
                }

                // Two files for one meeting: an edit made in an older Konfer,
                // which still writes by id. The newer copy is the one that was
                // edited last; the other stays on disk, untouched.
                if let existing = found[meeting.id], existing.modified >= modified {
                    Self.logger.notice("Two files for one meeting; reading the newer.")
                    continue
                }
                found[meeting.id] = (meeting, location, modified)
            }
        }
        scan(.root)

        // Assigned only when different, so a rescan that finds nothing new
        // doesn't redraw every view that reads the library.
        let loaded = found.values.map(\.meeting).sorted { $0.importedAt > $1.importedAt }
        if loaded != meetings { meetings = loaded }
        let loadedLocations = found.mapValues(\.location)
        if loadedLocations != locations { locations = loadedLocations }
        let loadedFolders = foundFolders.sorted()
        if loadedFolders != folders { folders = loadedFolders }
        lastSeen = Dictionary(
            found.values.map { ($0.location, (meeting: $0.meeting, modified: $0.modified)) },
            uniquingKeysWith: { first, _ in first }
        )

        for meeting in meetings {
            renameIfNamedByID(meeting)
        }
    }

    /// Gives a file named by meeting id — how every file was named before
    /// folders — its meeting's title instead.
    ///
    /// Only an id-name is renamed, so a name the user chose in Finder is never
    /// taken back.
    private func renameIfNamedByID(_ meeting: Meeting) {
        guard let location = locations[meeting.id],
              location.filename.lowercased() == "\(meeting.id.uuidString).json".lowercased()
        else { return }

        let source = url(of: location)
        let destination = LibraryName.available(
            filename(for: meeting),
            extension: "json",
            in: url(of: location.folder)
        )
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            locations[meeting.id] = Location(folder: location.folder, filename: destination.lastPathComponent)
        } catch {
            Self.logger.error("Could not rename a transcript: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Writing

    /// Writes a meeting, renaming its file first when its title changed.
    ///
    /// Only then: a save for any other reason leaves the name alone, which is
    /// what keeps a name given in Finder. The rename is a move made before the
    /// write, so a crash in between leaves one file under the new name holding
    /// the old title — never two files, and never none.
    private func save(_ meeting: Meeting, previousTitle: String) {
        if meeting.title != previousTitle, let location = locations[meeting.id] {
            let source = url(of: location)
            let destination = LibraryName.available(
                filename(for: meeting),
                extension: "json",
                in: url(of: location.folder),
                own: source
            )
            do {
                // The id-name is the one a stranded file is still read and
                // renamed from.
                try LibraryName.move(source, to: destination, temporaryName: "\(meeting.id.uuidString).json")
                locations[meeting.id] = Location(folder: location.folder, filename: destination.lastPathComponent)
            } catch {
                Self.logger.error("Could not rename a transcript: \(error.localizedDescription, privacy: .public)")
            }
        }
        write(meeting)
    }

    private func write(_ meeting: Meeting) {
        guard let location = locations[meeting.id] else { return }
        try? FileManager.default.createDirectory(
            at: url(of: location.folder),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(meeting) else { return }
        let file = url(of: location)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        // Remembered, so the next rescan knows this file is already read.
        if let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
            lastSeen[location] = (meeting, modified)
        }
    }

    // MARK: - Folders, internally

    /// Moves or renames a folder, and follows it with everything that named
    /// anything inside it.
    private func relocate(_ folder: MeetingFolder, into parent: MeetingFolder, named name: String) -> MeetingFolder? {
        guard !folder.isRoot, exists(folder), exists(parent) else { return nil }
        let source = url(of: folder)
        let destination = LibraryName.available(name, in: url(of: parent), own: source)
        do {
            try LibraryName.move(source, to: destination, temporaryName: UUID().uuidString)
        } catch {
            Self.logger.error("Could not move a folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let moved = parent.appending(destination.lastPathComponent)
        rebase(folder, to: moved)
        return moved
    }

    /// Everything that was at or under `old` is now at or under `new`.
    private func rebase(_ old: MeetingFolder, to new: MeetingFolder) {
        folders = folders.map { $0.moving(old, to: new) }.sorted()
        for (id, location) in locations where old.contains(location.folder) {
            locations[id] = Location(folder: location.folder.moving(old, to: new), filename: location.filename)
        }
    }

    private func exists(_ folder: MeetingFolder) -> Bool {
        folder.isRoot || folders.contains(folder)
    }

    private func filename(for meeting: Meeting) -> String {
        LibraryName.sanitized(meeting.title)
    }

    private func url(of location: Location) -> URL {
        url(of: location.folder).appendingPathComponent(location.filename, isDirectory: false)
    }
}

// MARK: - Location

extension MeetingStore {

    /// Where a meeting's file is: the folder, and its name in it.
    nonisolated struct Location: Hashable, Sendable {
        var folder: MeetingFolder
        var filename: String
    }
}
