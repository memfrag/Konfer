//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import OSLog

/// Moves the library from where Snoopy kept it to where Konfer does.
///
/// The app was renamed after it had already been storing transcripts and
/// several gigabytes of speech models in `Application Support/Snoopy`. Renaming
/// the path without moving the contents would present as a lost library and an
/// unexplained re-download, so the folder is moved once, on launch.
///
/// Deliberately conservative: it moves only when the old folder exists and the
/// new one does not, so it cannot merge two libraries or overwrite a newer one.
/// After a successful move there is nothing left to find, and it does nothing
/// on every launch thereafter.
nonisolated enum LibraryMigration {

    private static let logger = Logger(subsystem: "pizza.martin.Konfer", category: "Migration")

    /// What the folder was called before the app was renamed.
    static let legacyFolderName = "Snoopy"

    /// Where the old app kept everything.
    static var legacyDirectory: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(legacyFolderName, isDirectory: true)
    }

    /// Whether a move happened, so this can be tested without the real
    /// Application Support directory.
    @discardableResult
    static func migrateIfNeeded(
        from legacy: URL? = legacyDirectory,
        to current: URL = LibraryLocation.directory
    ) -> Bool {
        let fileManager = FileManager.default
        guard let legacy else { return false }

        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: current.path) else { return false }

        do {
            try fileManager.createDirectory(
                at: current.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: current)
            logger.info("Moved the library from \(legacyFolderName, privacy: .public) to Konfer.")
            return true
        } catch {
            // Not fatal: the app still runs, with an empty library and models to
            // fetch again. Losing the transcripts silently would be worse than
            // saying so in the log.
            logger.error("Could not move the library: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
