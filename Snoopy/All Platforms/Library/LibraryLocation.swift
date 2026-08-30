//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Where Snoopy keeps the meeting library.
///
/// Transcripts live here; audio does not. The library stores the path to the
/// user's own recording and leaves the file where they put it, which means a
/// meeting can outlive its audio. That case is handled when a meeting is
/// opened, not swept for at launch.
///
enum LibraryLocation {

    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base.appendingPathComponent("Snoopy", isDirectory: true)
    }

    static var meetingsDirectory: URL {
        directory.appendingPathComponent("Meetings", isDirectory: true)
    }

    static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(
            at: meetingsDirectory,
            withIntermediateDirectories: true
        )
    }
}
