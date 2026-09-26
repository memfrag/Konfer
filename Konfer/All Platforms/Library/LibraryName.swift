//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Names for the files and folders the meeting library puts on disk.
///
/// The library is a directory the user can see and rearrange in Finder, so
/// its files are named after what they hold. That makes their names the
/// user's text, and user's text is not always a safe filename.
nonisolated enum LibraryName {

    /// Room left for a numeric suffix and an extension within the 255 bytes a
    /// filename may take.
    static let maximumLength = 200

    /// A name that is safe to put on disk, made from a title.
    ///
    /// A leading dot is the one that matters most: it would make a hidden
    /// file, which the library skips when it reads the disk, so the meeting
    /// would quietly disappear from the sidebar the next time Konfer started.
    static func sanitized(_ title: String, fallback: String = "Untitled") -> String {
        var name = String(String.UnicodeScalarView(
            title.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        // A slash separates path components, and Finder shows a colon as one.
        name = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") {
            name.removeFirst()
            name = name.trimmingCharacters(in: .whitespaces)
        }
        while name.utf8.count > maximumLength {
            name.removeLast()
        }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? fallback : name
    }

    /// The first of `name`, `name 2`, `name 3`… that nothing in `directory`
    /// already uses.
    ///
    /// Asks the disk rather than the library, because the library skips files
    /// it can't read — a transcript from a newer Konfer, something the user
    /// put there — and a name taken by one of those is still taken. The disk
    /// also answers with its own case rules, so on the usual case-insensitive
    /// volume "kickoff" clashes with "Kickoff".
    ///
    /// `own` is the file or folder being renamed, whose current name never
    /// counts against it — renaming "kickoff" to "Kickoff" is not a clash.
    static func available(
        _ name: String,
        extension pathExtension: String? = nil,
        in directory: URL,
        own: URL? = nil
    ) -> URL {
        var number = 1
        while true {
            let base = number == 1 ? name : "\(name) \(number)"
            let candidate = pathExtension.map {
                directory.appendingPathComponent("\(base).\($0)", isDirectory: false)
            } ?? directory.appendingPathComponent(base, isDirectory: true)

            if let own, isSameEntry(candidate, own) { return candidate }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    /// Whether two URLs name the same entry once case is ignored — the only
    /// way two different spellings can reach one file.
    static func isSameEntry(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path.lowercased() == rhs.standardizedFileURL.path.lowercased()
    }

    /// Moves a file or folder, including a rename that changes only its case.
    ///
    /// A case-only rename goes by way of a temporary name, because a
    /// case-insensitive volume considers the destination to exist already.
    /// `temporaryName` is what a crash in between leaves behind, so the
    /// caller picks one the library still reads.
    static func move(_ source: URL, to destination: URL, temporaryName: String) throws {
        let fileManager = FileManager.default
        guard source.standardizedFileURL.path != destination.standardizedFileURL.path else { return }

        if isSameEntry(source, destination) {
            let temporary = source.deletingLastPathComponent()
                .appendingPathComponent(temporaryName)
            try fileManager.moveItem(at: source, to: temporary)
            try fileManager.moveItem(at: temporary, to: destination)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}
