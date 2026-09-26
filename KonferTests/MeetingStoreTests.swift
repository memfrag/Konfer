//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The library skips a meeting it can't decode rather than failing to open,
/// which is only safe for as long as nothing then writes over the skipped file.
@MainActor
struct MeetingStoreTests {

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func meeting(title: String) -> Meeting {
        Meeting(
            id: UUID(),
            title: title,
            audioPath: "/tmp/\(title).m4a",
            duration: 60,
            importedAt: Date(),
            language: .english,
            speakers: [SpeakerLabel(id: "Speaker 1", name: "Anna")],
            utterances: []
        )
    }

    @Test("A meeting that can't be decoded is skipped, and left untouched by writes to the others")
    func undecodableMeetingSurvivesWrites() throws {
        let directory = try scratch()
        let brokenURL = directory.appendingPathComponent("\(UUID().uuidString).json")
        let broken = Data(#"{"title" : "Truncated", "utterances" : ["#.utf8)
        try broken.write(to: brokenURL)

        let store = MeetingStore(directory: directory)
        #expect(store.meetings.isEmpty)

        let standup = meeting(title: "Standup")
        store.add(standup)
        store.modify(standup.id) { $0.title = "Standup, renamed" }
        store.add(meeting(title: "Retro"))
        store.delete(standup.id)

        #expect(try Data(contentsOf: brokenURL) == broken)
        #expect(MeetingStore(directory: directory).meetings.map(\.title) == ["Retro"])
    }
}
