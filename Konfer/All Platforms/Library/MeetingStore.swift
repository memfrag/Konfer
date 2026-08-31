//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// The meeting library: one JSON file per meeting, newest first.
///
/// Every mutation writes through immediately. Meetings are small enough
/// (a few hundred KB for an hour) that batching saves would add risk without
/// buying anything.
///
@Observable @MainActor
final class MeetingStore {

    private(set) var meetings: [Meeting] = []

    @ObservationIgnored
    private let directory: URL

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

    // MARK: - Mutation

    func add(_ meeting: Meeting) {
        meetings.insert(meeting, at: 0)
        write(meeting)
    }

    func update(_ meeting: Meeting) {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        meetings[index] = meeting
        write(meeting)
    }

    /// Applies an edit to the meeting with the given id and persists the result.
    func modify(_ id: UUID, _ transform: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        transform(&meetings[index])
        write(meetings[index])
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(for: id))
        WaveformStore.removeCache(for: id)
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func load() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        meetings = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Meeting.self, from: data)
            }
            // Written by a newer version of the app: skip rather than crash or
            // silently mangle. Nothing in v1 can produce this.
            .filter { $0.schemaVersion <= Meeting.currentSchemaVersion }
            .sorted { $0.importedAt > $1.importedAt }
    }

    private func write(_ meeting: Meeting) {
        LibraryLocation.ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(meeting) else { return }
        try? data.write(to: fileURL(for: meeting.id), options: .atomic)
    }
}
