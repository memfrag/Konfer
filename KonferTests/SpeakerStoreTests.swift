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

    @Test("A roster that can't be decoded is moved aside, not overwritten by the next enroll")
    func corruptRosterSurvivesEnroll() throws {
        let directory = try scratch()
        let rosterURL = directory.appendingPathComponent("speakers.json")
        let corrupt = Data(#"[{"createdAt" : 780000000, "embedding" : [0.5, 0.2"#.utf8)
        try corrupt.write(to: rosterURL)

        let store = SpeakerStore(directory: directory)
        #expect(store.profiles.isEmpty)

        store.enroll(name: "Anna", embedding: [1, 0])

        let setAside = try unreadableRosters(in: directory)
        #expect(setAside.count == 1)
        #expect(try Data(contentsOf: try #require(setAside.first)) == corrupt)
        #expect(SpeakerStore(directory: directory).profiles.map(\.name) == ["Anna"])
    }

    @Test("A roster that can't even be read is moved aside too")
    func unreadableRosterIsSetAside() throws {
        let directory = try scratch()
        let rosterURL = directory.appendingPathComponent("speakers.json")
        try Data("[]".utf8).write(to: rosterURL)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: rosterURL.path)

        let store = SpeakerStore(directory: directory)
        store.enroll(name: "Anna", embedding: [1, 0])

        #expect(try unreadableRosters(in: directory).count == 1)
        #expect(SpeakerStore(directory: directory).profiles.map(\.name) == ["Anna"])
    }

    @Test("With no roster on disk the store starts empty and sets nothing aside")
    func missingRosterStartsEmpty() throws {
        let directory = try scratch()

        let store = SpeakerStore(directory: directory)
        #expect(store.profiles.isEmpty)

        store.enroll(name: "Anna", embedding: [1, 0])

        #expect(try unreadableRosters(in: directory).isEmpty)
        #expect(SpeakerStore(directory: directory).profiles.map(\.name) == ["Anna"])
    }

    private func unreadableRosters(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("speakers.unreadable-") }
    }
}
