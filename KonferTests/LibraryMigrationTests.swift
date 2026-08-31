//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Moving the library when the app was renamed from Snoopy to Konfer.
///
/// This runs once, on a machine that already holds someone's transcripts and
/// several gigabytes of models. Getting it wrong looks like a lost library, so
/// it is tested against real directories rather than reasoned about.
struct LibraryMigrationTests {

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonferMigration-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeLibrary(at url: URL, marker: String) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Meetings"), withIntermediateDirectories: true
        )
        try marker.write(
            to: url.appendingPathComponent("Meetings/meeting.json"),
            atomically: true, encoding: .utf8
        )
    }

    private func marker(in url: URL) -> String? {
        try? String(contentsOf: url.appendingPathComponent("Meetings/meeting.json"), encoding: .utf8)
    }

    @Test("An old library is moved across, contents and all")
    func movesTheOldLibrary() throws {
        let root = temporaryDirectory()
        let legacy = root.appendingPathComponent("Snoopy")
        let current = root.appendingPathComponent("Konfer")
        try makeLibrary(at: legacy, marker: "the transcripts")

        #expect(LibraryMigration.migrateIfNeeded(from: legacy, to: current))

        #expect(marker(in: current) == "the transcripts")
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
    }

    @Test("A library already under the new name is left alone")
    func doesNotOverwriteAnExistingLibrary() throws {
        let root = temporaryDirectory()
        let legacy = root.appendingPathComponent("Snoopy")
        let current = root.appendingPathComponent("Konfer")
        try makeLibrary(at: legacy, marker: "the old one")
        try makeLibrary(at: current, marker: "the one in use")

        #expect(LibraryMigration.migrateIfNeeded(from: legacy, to: current) == false)

        // Merging two libraries, or clobbering the newer one, would both be
        // worse than leaving the old folder sitting there.
        #expect(marker(in: current) == "the one in use")
        #expect(marker(in: legacy) == "the old one")
    }

    @Test("Nothing to move is not a failure")
    func doesNothingWithoutAnOldLibrary() {
        let root = temporaryDirectory()
        let legacy = root.appendingPathComponent("Snoopy")
        let current = root.appendingPathComponent("Konfer")

        #expect(LibraryMigration.migrateIfNeeded(from: legacy, to: current) == false)
        #expect(!FileManager.default.fileExists(atPath: current.path))
    }

    @Test("Running it twice moves once and then does nothing")
    func isIdempotent() throws {
        let root = temporaryDirectory()
        let legacy = root.appendingPathComponent("Snoopy")
        let current = root.appendingPathComponent("Konfer")
        try makeLibrary(at: legacy, marker: "the transcripts")

        #expect(LibraryMigration.migrateIfNeeded(from: legacy, to: current))
        #expect(LibraryMigration.migrateIfNeeded(from: legacy, to: current) == false)
        #expect(marker(in: current) == "the transcripts")
    }
}
