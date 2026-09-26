//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The roster is decoded all or nothing and saved over itself, so a change to
/// what a person is has to keep reading every file written before it.
@MainActor
struct SpeakerStoreTests {

    private func scratch() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakerStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("A roster written before notes existed still loads, everyone in it")
    func rosterWithoutNotesLoads() throws {
        let directory = try scratch()
        let json = """
        [
          {
            "createdAt" : 780000000,
            "embedding" : [0.5, 0.25],
            "id" : "3A96F3AA-54D8-4E25-A884-844020357A86",
            "name" : "Anna",
            "sampleCount" : 3,
            "updatedAt" : 780100000
          },
          {
            "createdAt" : 780000000,
            "embedding" : [0.1, 0.9],
            "id" : "B7B452F7-42E7-462C-A5F1-007620190CBF",
            "name" : "Bo",
            "sampleCount" : 1,
            "updatedAt" : 780000000
          }
        ]
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("speakers.json"))

        let store = SpeakerStore(directory: directory)

        #expect(store.profiles.map(\.name) == ["Anna", "Bo"])
        #expect(store.profiles.allSatisfy { $0.note == nil })
    }

    @Test("A note is kept trimmed, survives a reload, and emptying it removes it")
    func noteRoundTrips() throws {
        let directory = try scratch()
        let store = SpeakerStore(directory: directory)
        store.enroll(name: "Anna", embedding: [1, 0])
        let id = try #require(store.profiles.first?.id)

        store.setNote("  Product lead at the agency\n", for: id)
        #expect(SpeakerStore(directory: directory).profile(id)?.note == "Product lead at the agency")

        store.setNote("   ", for: id)
        #expect(SpeakerStore(directory: directory).profile(id)?.note == nil)
    }

    @Test("Writing a note doesn't change when the person was last heard")
    func noteLeavesLastHeardAlone() throws {
        let store = SpeakerStore(directory: try scratch())
        store.enroll(name: "Anna", embedding: [1, 0])
        let before = try #require(store.profiles.first)

        store.setNote("Product lead", for: before.id)

        #expect(store.profile(before.id)?.updatedAt == before.updatedAt)
    }

    @Test("Merging keeps the kept person's note, or takes the other's if they had none")
    func mergeCarriesNotes() throws {
        let store = SpeakerStore(directory: try scratch())
        store.enroll(name: "Anna", embedding: [1, 0])
        store.enroll(name: "Anna L", embedding: [0.9, 0.1])
        store.enroll(name: "Bo", embedding: [0, 1])
        let anna = try #require(store.profiles.first { $0.name == "Anna" }?.id)
        let annaL = try #require(store.profiles.first { $0.name == "Anna L" }?.id)
        let bo = try #require(store.profiles.first { $0.name == "Bo" }?.id)

        store.setNote("Product lead", for: annaL)
        store.merge(annaL, into: anna)
        #expect(store.profile(anna)?.note == "Product lead")

        store.setNote("Designer", for: bo)
        store.merge(anna, into: bo)
        #expect(store.profile(bo)?.note == "Designer")
    }
}
