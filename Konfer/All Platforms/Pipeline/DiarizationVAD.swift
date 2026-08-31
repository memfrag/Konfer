//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import WhisperKit

/// A voice activity detector backed by the diarizer's own segmentation.
///
/// WhisperKit's default `EnergyVAD` thresholds frame RMS at a fixed 0.02.
/// Measured on a real meeting recording, that marks only 67.8% of frames as
/// speech — not because the room is noisy (the noise floor sits at 0.0033, well
/// below the threshold) but because a far-field mic makes a quarter of the
/// speech quieter than the threshold. Lowering it doesn't help: the chunker
/// splits on the longest silence it can find, so removing silences makes it cut
/// mid-word instead, which is what makes Whisper hallucinate.
///
/// pyannote has already solved this properly by the time we transcribe. This
/// converts its segments into the frame mask WhisperKit expects.
///
nonisolated final class DiarizationVAD: VoiceActivityDetector, @unchecked Sendable {

    private let regions: [SpeechRegion]

    init(regions: [SpeechRegion], sampleRate: Int = 16000, frameLength: Float = 0.1) {
        self.regions = regions
        super.init(
            sampleRate: sampleRate,
            frameLengthSamples: Int(frameLength * Float(sampleRate)),
            frameOverlapSamples: 0
        )
    }

    required override init(sampleRate: Int, frameLengthSamples: Int, frameOverlapSamples: Int) {
        regions = []
        super.init(
            sampleRate: sampleRate,
            frameLengthSamples: frameLengthSamples,
            frameOverlapSamples: frameOverlapSamples
        )
    }

    override func voiceActivity(in waveform: [Float]) -> [Bool] {
        let frameCount = Int((Double(waveform.count) / Double(frameLengthSamples)).rounded(.up))
        guard frameCount > 0 else { return [] }
        guard !regions.isEmpty else {
            // No diarization to go on: treat everything as speech rather than
            // silently dropping audio. Worst case we transcribe some silence.
            return Array(repeating: true, count: frameCount)
        }

        let frameSeconds = Double(frameLengthSamples) / Double(sampleRate)
        var mask = [Bool](repeating: false, count: frameCount)
        var cursor = 0

        for region in regions {
            let first = max(0, Int((region.start / frameSeconds).rounded(.down)))
            let last = min(frameCount - 1, Int((region.end / frameSeconds).rounded(.up)))
            guard first <= last else { continue }
            cursor = max(cursor, first)
            for index in first...last { mask[index] = true }
        }
        return mask
    }
}
