//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// The roster of people Konfer has learned to recognise.
///
/// **Matches are suggestions, never applied automatically.** A false positive
/// would silently stamp a real person's name across an hour of transcript,
/// which is a worse outcome than the small friction of confirming a name. So a
/// match becomes an ``EnrollmentSuggestion`` on the speaker chip, and only an
/// explicit acceptance names the speaker and reinforces the profile.
///
@Observable @MainActor
final class SpeakerStore {

    /// Cosine distance below which two embeddings are worth suggesting as the
    /// same person. Deliberately conservative: a missed suggestion costs one
    /// rename, a wrong one costs trust in every label in the app.
    static let suggestionThreshold: Float = 0.45

    private(set) var profiles: [SpeakerProfile] = []

    @ObservationIgnored
    private let fileURL: URL

    init(directory: URL = LibraryLocation.directory) {
        fileURL = directory.appendingPathComponent("speakers.json")
        load()
    }

    // MARK: - Access

    func profile(_ id: UUID) -> SpeakerProfile? {
        profiles.first { $0.id == id }
    }

    // MARK: - Matching

    /// The closest profile to `embedding`, if it is close enough to suggest.
    func suggestion(for embedding: [Float]) -> EnrollmentSuggestion? {
        guard !embedding.isEmpty else { return nil }

        var best: (profile: SpeakerProfile, distance: Float)?
        for profile in profiles {
            let distance = VoiceEmbedding.distance(profile.embedding, embedding)
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (profile, distance)
            }
        }

        guard let best, best.distance <= Self.suggestionThreshold else { return nil }
        return EnrollmentSuggestion(
            profileID: best.profile.id,
            name: best.profile.name,
            distance: best.distance
        )
    }

    /// Annotates a meeting's speakers with any enrollment suggestions.
    func annotate(_ speakers: [SpeakerLabel]) -> [SpeakerLabel] {
        speakers.map { speaker in
            var speaker = speaker
            speaker.suggestion = suggestion(for: speaker.embedding)
            return speaker
        }
    }

    // MARK: - Enrollment

    /// Records that `embedding` belongs to `name`.
    ///
    /// Reinforces an existing profile when the name already exists (whether the
    /// user accepted a suggestion or typed the name again), otherwise enrolls a
    /// new person.
    func enroll(name: String, embedding: [Float]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !embedding.isEmpty else { return }

        if let index = profiles.firstIndex(where: {
            $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            profiles[index].reinforce(with: embedding)
        } else {
            profiles.append(SpeakerProfile(name: trimmed, embedding: embedding))
        }
        save()
    }

    func accept(_ suggestion: EnrollmentSuggestion, embedding: [Float]) {
        guard let index = profiles.firstIndex(where: { $0.id == suggestion.profileID })
        else { return }
        profiles[index].reinforce(with: embedding)
        save()
    }

    func rename(_ profileID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == profileID })
        else { return }
        profiles[index].name = trimmed
        profiles[index].updatedAt = Date()
        save()
    }

    /// Replaces a person's note; an empty one removes it.
    ///
    /// Leaves `updatedAt` alone, unlike a rename: the People window shows it
    /// as when the person was last heard, and writing about someone is not
    /// hearing them.
    func setNote(_ note: String, for profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard profiles[index].note != value else { return }
        profiles[index].note = value
        save()
    }

    func delete(_ profileID: UUID) {
        profiles.removeAll { $0.id == profileID }
        save()
    }

    /// Folds `source` into `destination` — the two profiles were the same
    /// person all along.
    func merge(_ source: UUID, into destination: UUID) {
        guard source != destination,
              let sourceIndex = profiles.firstIndex(where: { $0.id == source }),
              let destinationIndex = profiles.firstIndex(where: { $0.id == destination })
        else { return }

        let absorbed = profiles[sourceIndex]
        profiles[destinationIndex].reinforce(with: absorbed.embedding)
        // The person being kept wins, but a note is not something to lose
        // just because it was written on the other half of the same person.
        if profiles[destinationIndex].note == nil {
            profiles[destinationIndex].note = absorbed.note
        }
        profiles.remove(at: sourceIndex)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        profiles = (try? JSONDecoder().decode([SpeakerProfile].self, from: data)) ?? []
    }

    private func save() {
        LibraryLocation.ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
