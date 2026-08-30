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

nonisolated extension SpeechRegion {

    /// Seconds of slack added around each diarization segment.
    /// `SNOOPY_VAD_PADDING` overrides it for comparison runs.
    static var padding: TimeInterval {
        ProcessInfo.processInfo.environment["SNOOPY_VAD_PADDING"]
            .flatMap(TimeInterval.init) ?? 0.4
    }

    /// Refines cut points to the quietest moment near each one.
    ///
    /// Diarization gaps are a decent first guess but not a reliable one —
    /// measured on a real meeting, one cut in three landed on a passage louder
    /// than the 75th percentile, and every cut had a far quieter spot within
    /// fifteen seconds. The samples are already in hand when slicing, so this
    /// looks at the audio itself rather than trusting the segmentation.
    ///
    /// - Parameters:
    ///   - cuts: Candidate cut times, in seconds.
    ///   - samples: The whole recording, mono.
    ///   - searchSeconds: How far either side of a candidate to look.
    /// - Returns: Adjusted cut times, ascending.
    static func quietest(
        near cuts: [TimeInterval],
        in samples: [Float],
        sampleRate: Double,
        searchSeconds: TimeInterval = 15,
        windowSeconds: TimeInterval = 0.3
    ) -> [TimeInterval] {

        let windowLength = max(1, Int(windowSeconds * sampleRate))
        let reach = Int(searchSeconds * sampleRate)

        return cuts.map { cut in
            let centre = Int(cut * sampleRate)
            let lower = max(0, centre - reach)
            let upper = min(samples.count - windowLength, centre + reach)
            guard lower < upper else { return cut }

            var bestStart = centre
            var bestPeak = Float.greatestFiniteMagnitude

            // Step by a fraction of the window: fine enough to find a gap
            // between words, coarse enough to stay cheap on an hour of audio.
            let stride = max(1, windowLength / 3)
            for start in Swift.stride(from: lower, to: upper, by: stride) {
                var peak: Float = 0
                for index in Swift.stride(from: start, to: start + windowLength, by: 16) {
                    peak = max(peak, abs(samples[index]))
                    if peak >= bestPeak { break }
                }
                if peak < bestPeak {
                    bestPeak = peak
                    bestStart = start
                }
            }
            return Double(bestStart + windowLength / 2) / sampleRate
        }
    }

    /// Picks `count - 1` places to cut the recording, each in real silence.
    ///
    /// The aim is coarse parallelism without WhisperKit's chunker: a handful of
    /// long slices, each transcribed in one complete pass, cut where nobody is
    /// speaking. Boundaries are chosen by walking out from an even division to
    /// the nearest gap between speech regions, so a cut never lands mid-word.
    ///
    /// - Returns: Cut times in seconds, ascending. Empty when the recording is
    ///   too short to divide or no safe gap exists.
    static func cutPoints(
        in regions: [SpeechRegion],
        duration: TimeInterval,
        slices: Int,
        minimumSliceSeconds: TimeInterval = 60
    ) -> [TimeInterval] {

        guard slices > 1, duration > minimumSliceSeconds * Double(slices) else { return [] }

        // Silence between one region's end and the next one's start.
        let gaps: [(midpoint: TimeInterval, width: TimeInterval)] = zip(regions, regions.dropFirst())
            .map { (($0.end + $1.start) / 2, $1.start - $0.end) }
            .filter { $0.1 > 0 }
        guard !gaps.isEmpty else { return [] }

        var cuts: [TimeInterval] = []
        for index in 1..<slices {
            let target = duration * Double(index) / Double(slices)
            // Nearest gap to the ideal split, preferring wider gaps when two are
            // similarly close.
            let best = gaps.min {
                (abs($0.midpoint - target) - $0.width) < (abs($1.midpoint - target) - $1.width)
            }
            guard let best else { continue }
            let cut = best.midpoint
            // Keep slices apart, and never emit the same gap twice.
            if let previous = cuts.last, cut - previous < minimumSliceSeconds { continue }
            if cut > minimumSliceSeconds, duration - cut > minimumSliceSeconds {
                cuts.append(cut)
            }
        }
        return cuts
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
