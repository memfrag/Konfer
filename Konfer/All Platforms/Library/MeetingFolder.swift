//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A folder in the meeting library, named by its path below `Meetings/`.
///
/// A path rather than an id because the folders are real directories and
/// nothing else names them: a folder renamed in Finder is renamed here too,
/// the next time the library is read.
nonisolated struct MeetingFolder: Hashable, Comparable, Sendable {

    /// The folder names from the top of the library down. Empty for the top
    /// level itself.
    let components: [String]

    init(_ components: [String] = []) {
        self.components = components
    }

    /// The top of the library, where meetings land unless told otherwise.
    static let root = MeetingFolder()

    var isRoot: Bool { components.isEmpty }

    /// What the folder is called; empty for the top level.
    var name: String { components.last ?? "" }

    /// The folder this one is in, or nil for the top level.
    var parent: MeetingFolder? {
        isRoot ? nil : MeetingFolder(Array(components.dropLast()))
    }

    func appending(_ name: String) -> MeetingFolder {
        MeetingFolder(components + [name])
    }

    /// Whether `other` is this folder or somewhere inside it.
    func contains(_ other: MeetingFolder) -> Bool {
        other.components.starts(with: components)
    }

    /// `self` as it is after `old` became `new` — how a rename or move of a
    /// folder reaches everything inside it. Unchanged when `old` doesn't
    /// contain it.
    func moving(_ old: MeetingFolder, to new: MeetingFolder) -> MeetingFolder {
        guard old.contains(self) else { return self }
        return MeetingFolder(new.components + components.dropFirst(old.components.count))
    }

    func url(in library: URL) -> URL {
        components.reduce(library) { $0.appendingPathComponent($1, isDirectory: true) }
    }

    /// Parents before their children, and siblings in Finder's order, so a
    /// sorted list of folders reads as the outline it describes.
    static func < (lhs: MeetingFolder, rhs: MeetingFolder) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right {
            return left.localizedStandardCompare(right) == .orderedAscending
        }
        return lhs.components.count < rhs.components.count
    }
}
