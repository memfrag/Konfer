//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A known person, remembered across meetings by the sound of their voice.
nonisolated struct SpeakerProfile: Identifiable, Codable, Hashable, Sendable {

    let id: UUID
    var name: String

    /// Running mean of the voice embeddings accepted for this person.
    var embedding: [Float]

    /// How many meetings have contributed to `embedding`. Used to weight the
    /// running mean so one noisy meeting can't dominate an established profile.
    var sampleCount: Int

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        embedding: [Float],
        sampleCount: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.embedding = embedding
        self.sampleCount = sampleCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Folds a new observation into the running mean.
    mutating func reinforce(with observation: [Float]) {
        guard observation.count == embedding.count, !observation.isEmpty else {
            if embedding.isEmpty { embedding = observation }
            updatedAt = Date()
            return
        }
        let weight = Float(sampleCount)
        for index in embedding.indices {
            embedding[index] = (embedding[index] * weight + observation[index]) / (weight + 1)
        }
        sampleCount += 1
        updatedAt = Date()
    }
}
