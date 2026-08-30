//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio

/// A stretch of the recording that contains speech.
///
/// Snoopy diarizes before it transcribes, which means pyannote has already
/// worked out where the speech is by the time the recogniser runs. These
/// regions are that knowledge, handed forward so the recogniser doesn't have to
/// rediscover it with a cruder tool.
nonisolated struct SpeechRegion: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }
}

extension SpeechRegion {

    /// Seconds of slack added around each diarization segment.
    /// `SNOOPY_VAD_PADDING` overrides it for comparison runs.
    static var padding: TimeInterval {
        ProcessInfo.processInfo.environment["SNOOPY_VAD_PADDING"]
            .flatMap(TimeInterval.init) ?? 0.4
    }

    /// Collapses diarization segments into non-overlapping speech regions.
    ///
    /// - Parameter padding: Seconds added to each side before merging. Chunk
    ///   boundaries that land mid-word make Whisper hallucinate, so it is far
    ///   better to include a little silence than to clip the start of a word.
    static func regions(
        from segments: [TimedSpeakerSegment],
        padding: TimeInterval = 0.4
    ) -> [SpeechRegion] {

        let sorted = segments
            .map {
                SpeechRegion(
                    start: max(0, TimeInterval($0.startTimeSeconds) - padding),
                    end: TimeInterval($0.endTimeSeconds) + padding
                )
            }
            .sorted { $0.start < $1.start }

        var merged: [SpeechRegion] = []
        for region in sorted {
            if let last = merged.last, region.start <= last.end {
                merged[merged.count - 1] = SpeechRegion(
                    start: last.start,
                    end: max(last.end, region.end)
                )
            } else {
                merged.append(region)
            }
        }
        return merged
    }
}
