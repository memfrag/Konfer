//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

/// Distance and averaging over speaker embeddings.
///
/// FluidAudio's `SpeakerManager` also compares embeddings, but it is built
/// around the streaming diarizer's live speaker table — using it here would
/// mean maintaining that state just to borrow a distance function.
///
nonisolated enum VoiceEmbedding {

    /// Cosine distance in [0, 2]. Identical directions give 0.
    static func distance(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return .greatestFiniteMagnitude }

        var dot: Float = 0
        var lhsNorm: Float = 0
        var rhsNorm: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            lhsNorm += lhs[index] * lhs[index]
            rhsNorm += rhs[index] * rhs[index]
        }
        guard lhsNorm > 0, rhsNorm > 0 else { return .greatestFiniteMagnitude }
        return 1 - dot / (lhsNorm.squareRoot() * rhsNorm.squareRoot())
    }

    /// Duration-weighted mean of a cluster's segment embeddings.
    ///
    /// Weighting by duration keeps a long, clean stretch of speech from being
    /// outvoted by a handful of half-second fragments.
    static func mean(of segments: [TimedSpeakerSegment]) -> [Float] {
        let usable = segments.filter { !$0.embedding.isEmpty && $0.durationSeconds > 0 }
        guard let width = usable.first?.embedding.count, width > 0 else { return [] }

        var sum = [Float](repeating: 0, count: width)
        var totalWeight: Float = 0

        for segment in usable where segment.embedding.count == width {
            let weight = Float(segment.durationSeconds)
            for index in 0..<width {
                sum[index] += segment.embedding[index] * weight
            }
            totalWeight += weight
        }

        guard totalWeight > 0 else { return [] }
        return sum.map { $0 / totalWeight }
    }
}
