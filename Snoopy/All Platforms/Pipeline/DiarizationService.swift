//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

/// Speaker diarization — "who spoke when" — via FluidAudio's offline pipeline.
///
/// The offline pipeline (pyannote segmentation, WeSpeaker embeddings, VBx
/// clustering) is the best-quality option in FluidAudio and the right one for a
/// finished recording. The streaming diarizers exist for live audio, which is
/// out of scope.
///
/// `OfflineDiarizerManager` is a plain non-`Sendable` class, so it is created
/// and used entirely inside this actor. Models are loaded once and shared
/// across runs; only the lightweight manager is rebuilt per run, so a
/// speaker-count hint can vary between meetings.
///
actor DiarizationService {

    private var models: OfflineDiarizerModels?

    var isPrepared: Bool { models != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard models == nil else { return }
        models = try await OfflineDiarizerModels.load { update in
            progress(update.fractionCompleted)
        }
    }

    func unload() {
        models = nil
    }

    /// Runs diarization over a whole file.
    ///
    /// - Parameter expectedSpeakers: An optional exact speaker count. FluidAudio
    ///   treats it as a target rather than a guarantee, but when the user knows
    ///   how many people were in the room it measurably helps clustering.
    func diarize(
        _ url: URL,
        expectedSpeakers: Int?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [TimedSpeakerSegment] {

        guard let models else { throw PipelineError.modelsNotLoaded }

        var config = OfflineDiarizerConfig()
        if let expectedSpeakers, expectedSpeakers > 0 {
            config.clustering.numSpeakers = expectedSpeakers
        }

        let manager = OfflineDiarizerManager(config: config)
        manager.initialize(models: models)

        // `process(_ url:)` memory-maps and resamples internally, so an hour of
        // audio never lands in RAM whole.
        let result = try await manager.process(url) { done, total in
            guard total > 0 else { return }
            progress(Double(done) / Double(total))
        }

        progress(1)
        return result.segments
    }
}
