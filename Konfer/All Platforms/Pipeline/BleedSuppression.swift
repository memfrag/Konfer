//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Silences the microphone side wherever it is only hearing the call.
///
/// A call played over speakers reaches the microphone. Measured on a Mac Studio
/// — its own speakers at half volume, a USB microphone a desk apart, a synthetic
/// voice as the far end — the microphone's loudness tracks the call's with a
/// correlation of 0.73 at a lag of 20 ms, 43 dB below the digital copy. That is
/// quiet enough that attribution never confuses the two, and still loud enough
/// that the microphone side's diarization pass clusters it: the far end comes
/// back as somebody standing in the room, carrying their voice as its
/// embedding. Dropping unheard clusters from the roster hides that; this is
/// what stops it being recorded in the first place.
///
/// **Not echo cancellation.** Nothing is subtracted and no impulse response is
/// modelled, because neither is needed for the job: the stretches that invent a
/// speaker are the ones where the microphone hears *nothing but* the call, and
/// those can be recognised and silenced outright. Where somebody in the room is
/// also talking, their voice dominates the bleed by tens of decibels and the
/// frame is left exactly as it was. So double-talk is not cleaned up — it is
/// deliberately not touched.
///
/// Only the side file is gated. The fold that speech recognition reads is left
/// alone, because a word the gate misjudged would otherwise be a word missing
/// from the transcript, and the far end is on the other channel of that fold
/// regardless.
nonisolated enum BleedSuppression {

    /// How the call reaches the microphone in one recording.
    struct Coupling: Equatable, Sendable {

        /// Frames the microphone lags the system channel by, in
        /// ``SideEnvelope/frameDuration`` units.
        let lag: Int

        /// Energy ratio: microphone bleed energy over system energy. Squared
        /// amplitude, since ``SideEnvelope`` keeps mean squares.
        let gain: Float

        /// The share of the call's audible frames where the microphone held
        /// exactly what the bleed accounts for, 0...1. The evidence that there
        /// is bleed at all.
        let evidence: Float

        /// The microphone's own noise, in decibels. A frame no louder than
        /// this held nothing, whatever the call was doing.
        let noiseDecibels: Float

        var decibels: Float { 10 * log10(max(gain, .leastNormalMagnitude)) }
    }

    /// Below this share the microphone is not following the call and there is
    /// nothing to suppress.
    static let minimumEvidence: Float = 0.5

    /// A bleed further down than this is under the microphone's own noise and
    /// is not bleed. Measured, a Mac Studio's speakers reach its desk
    /// microphone 43 dB down and that microphone's noise floor is another 15 dB
    /// below *that*, so 60 is generous. It also stops a recording where the
    /// room and the call simply take turns from measuring as a coupled pair:
    /// the microphone's noise floor, being flat, looks like what an
    /// arbitrarily quiet bleed would predict.
    static let minimumDecibels: Float = -60

    /// How far a frame may sit from what the bleed predicts and still count as
    /// explained by it. Six decibels, which is a factor of four in energy:
    /// wide enough for the microphone's own noise to move a quiet frame
    /// around, narrow enough that a voice in the room does not fit inside it.
    static let inlierBand: Float = 6

    /// Lags searched, in frames — 0 to 200 ms. The 20 ms measured is the
    /// direct acoustic path plus output buffering; a Bluetooth speaker can add
    /// far more, and looking further costs one pass over the frames per lag.
    static let maximumLag = 10

    /// A frame is bleed alone when the microphone holds no more than this much
    /// more energy than the bleed accounts for. Three is 4.8 dB of headroom:
    /// enough that an imperfect estimate does not start gating speech, small
    /// enough that it still catches the bleed itself.
    static let tolerance: Float = 3

    // MARK: - Measuring

    /// Estimates how much of the call the microphone is hearing, or nil when
    /// the answer is "not enough to matter".
    ///
    /// Everything here is decibels, not energy, and that is load-bearing
    /// rather than cosmetic. In linear energy a handful of frames where
    /// somebody in the room speaks are tens of times larger than every bleed
    /// frame put together, and they drown out the thing being measured. In
    /// decibels the bleed sits a constant distance below the call, which is
    /// what makes it recognisable, and a loud frame is merely 20 higher rather
    /// than a hundred times bigger.
    ///
    /// Only frames where the call is audible are looked at, which is the
    /// second load-bearing part. A conversation alternates: the room talks,
    /// then the far end answers. Measured across the whole recording, the
    /// microphone is loudest exactly where the call is silent, and no
    /// correlation survives that. Inside the call's own speech the question is
    /// well posed — is the microphone tracking it, or doing something of its
    /// own?
    ///
    /// And the evidence is a count of frames rather than a correlation, which
    /// is the third. Pearson correlation over those frames is dominated by
    /// whichever few are loudest, so genuine double-talk in a tenth of them
    /// drags it under any usable threshold. Counting the frames that sit where
    /// the bleed predicts does not care how far the others are away.
    ///
    /// Loudness, not samples: phase, room colouring and the speaker's
    /// frequency response are all irrelevant to the only question being asked,
    /// which is whether a frame is the call or somebody in the room.
    static func coupling(microphone: [Float], system: [Float]) -> Coupling? {
        let count = min(microphone.count, system.count)
        guard count > maximumLag + minimumFrames else { return nil }

        let micLevels = decibels(microphone, count: count)
        let systemLevels = decibels(system, count: count)
        guard let loudest = systemLevels.max(), loudest > silence + 10 else { return nil }
        let audible = loudest - audibleRange

        var best: Coupling?
        for lag in 0...maximumLag {
            guard let offset = offset(micLevels, systemLevels, lag: lag, over: audible),
                  offset > minimumDecibels
            else { continue }
            let evidence = evidence(
                micLevels, systemLevels, lag: lag, over: audible, offset: offset
            )
            guard evidence > max(minimumEvidence, best?.evidence ?? 0) else { continue }
            best = Coupling(
                lag: lag,
                gain: pow(10, offset / 10),
                evidence: evidence,
                noiseDecibels: noise(micLevels)
            )
        }
        return best
    }

    /// How far below its loudest frame the call still counts as audible. 20 dB
    /// keeps the syllables and leaves out the gaps between words, where the
    /// microphone has nothing to track.
    private static let audibleRange: Float = 20

    /// Frames the call has to be audible in before any of this is worth
    /// answering.
    private static let minimumFrames = 5

    /// Frame energies as decibels, floored so digital silence is a number.
    private static func decibels(_ frames: [Float], count: Int) -> [Float] {
        frames.prefix(count).map { 10 * log10(max($0, 1e-12)) }
    }

    /// The level a frame of pure digital silence comes out at.
    private static let silence: Float = -120

    /// The microphone's noise floor, as its tenth-quietest-percent frame.
    ///
    /// Every recording has gaps between words, so a low percentile is what the
    /// microphone reads when nothing is reaching it. Needed because the call's
    /// own gaps and its quietest syllables predict a bleed below that floor,
    /// and a frame cannot be quieter than the noise it is sitting in — without
    /// this the gate would leave those frames alone, which are precisely the
    /// ones holding nothing at all.
    private static func noise(_ levels: [Float]) -> Float {
        guard !levels.isEmpty else { return silence }
        var sorted = levels
        sorted.sort()
        return sorted[sorted.count / 10]
    }

    /// How far below the call the bleed sits, in decibels: the *lowest*
    /// plausible offset rather than the average one.
    ///
    /// A recording where somebody speaks in the room has frames whose
    /// microphone level is their voice, not the bleed, and averaging those in
    /// would overstate the coupling — which would gate real speech away. The
    /// tenth percentile of the difference, over frames where the call is
    /// clearly audible, is the bleed alone: in every frame at least that
    /// quiet, nothing but the call was reaching the microphone.
    private static func offset(
        _ microphone: [Float],
        _ system: [Float],
        lag: Int,
        over audible: Float
    ) -> Float? {
        var differences: [Float] = []
        for index in 0..<(system.count - lag) where system[index] > audible {
            differences.append(microphone[index + lag] - system[index])
        }
        guard differences.count >= minimumFrames else { return nil }
        differences.sort()
        return differences[differences.count / 10]
    }

    /// The share of the call's audible frames where the microphone sits within
    /// ``inlierBand`` of what a bleed at `offset` predicts.
    private static func evidence(
        _ microphone: [Float],
        _ system: [Float],
        lag: Int,
        over audible: Float,
        offset: Float
    ) -> Float {
        var audibleFrames = 0
        var explained = 0
        for index in 0..<(system.count - lag) where system[index] > audible {
            audibleFrames += 1
            let predicted = system[index] + offset
            if abs(microphone[index + lag] - predicted) <= inlierBand { explained += 1 }
        }
        guard audibleFrames >= minimumFrames else { return 0 }
        return Float(explained) / Float(audibleFrames)
    }

    // MARK: - Gating

    /// Which microphone frames are the call and nothing else.
    ///
    /// - Returns: One flag per microphone frame, true where the frame should be
    ///   silenced.
    static func gate(
        microphone: [Float],
        system: [Float],
        coupling: Coupling
    ) -> [Bool] {
        let micLevels = decibels(microphone, count: microphone.count)
        let systemLevels = decibels(system, count: system.count)
        let headroom = 10 * log10(tolerance)

        return micLevels.indices.map { index in
            let source = index - coupling.lag
            guard source >= 0, source < systemLevels.count else { return false }
            // Silenced where the microphone holds no more than the bleed
            // accounts for — or no more than its own noise, which is the same
            // statement about a frame that holds nothing at all.
            let explained = max(
                systemLevels[source] + coupling.decibels,
                coupling.noiseDecibels
            )
            return micLevels[index] <= explained + headroom
        }
    }
}
