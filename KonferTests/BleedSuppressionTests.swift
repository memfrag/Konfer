//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Deciding which microphone frames hold nothing but the call, from the two
/// sides' loudness alone. Fixtures in the envelope domain — no audio, no
/// models.
///
/// The numbers come from a measurement: a Mac Studio's speakers reach its own
/// desk microphone about 43 dB down, with the loudness of the two sides
/// tracking at r = 0.73 and a lag of 20 ms, which is one envelope frame.
struct BleedSuppressionTests {

    /// What a real microphone reads when nothing is reaching it: its own noise,
    /// not digital zero. −80 dB, about 15 dB under the bleed measured on
    /// hardware, which is what makes a bleed recognisable at all.
    private static let noise: Float = 1e-8

    /// A speech-like envelope — syllables spread over a wide range of
    /// loudness, with true silence in the gaps, which is what the system side
    /// of a tap actually contains.
    ///
    /// The range matters rather than the level: what marks a frame as bleed is
    /// the microphone rising and falling *with* the call, so a fixture whose
    /// syllables are all the same loudness would let a constant noise floor
    /// pass as a very quiet bleed. Deterministic, so a failure is reproducible.
    private func speech(_ count: Int, level: Float, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let unit = Float((state >> 33) % 1_000) / 1_000
            guard unit >= 0.25 else { return 0 }
            // 0 to 24 dB below the loudest syllable.
            return level * pow(10, -24 * (1 - unit) / 10)
        }
    }

    /// What the microphone hears of that call: the same envelope `lag` frames
    /// later and `gain` times quieter, never below the microphone's own noise.
    private func heard(_ system: [Float], gain: Float, lag: Int) -> [Float] {
        let delayed = [Float](repeating: 0, count: lag) + system.dropLast(lag)
        return delayed.map { max(Self.noise, $0 * gain) }
    }

    // MARK: - Measuring

    @Test("A microphone following the call one frame behind is measured as bleed")
    func couplingIsFound() throws {
        let system = speech(150, level: 0.01)
        let microphone = heard(system, gain: 0.000_05, lag: 1)

        let coupling = try #require(
            BleedSuppression.coupling(microphone: microphone, system: system)
        )
        #expect(coupling.lag == 1)
        #expect(coupling.evidence > 0.9)
        // 5e-5 in energy is 43 dB down, the measured figure.
        #expect(coupling.decibels < -40)
        #expect(coupling.decibels > -46)
    }

    @Test("Turn-taking is not bleed")
    func alternatingSpeechIsNotCoupled() {
        // The room answers the call rather than talking along with it, which
        // leaves the two sides anti-correlated.
        let system = speech(100, level: 0.01).enumerated().map { $0.offset < 50 ? $0.element : 0 }
        let microphone = speech(100, level: 0.02, seed: 9)
            .enumerated()
            .map { $0.offset < 50 ? Self.noise : max(Self.noise, $0.element) }

        #expect(BleedSuppression.coupling(microphone: microphone, system: system) == nil)
    }

    @Test("A silent call side is nothing to measure")
    func silentSystemSideIsNotCoupled() {
        let system = [Float](repeating: 0, count: 100)
        let microphone = speech(100, level: 0.02).map { max(Self.noise, $0) }

        #expect(BleedSuppression.coupling(microphone: microphone, system: system) == nil)
    }

    @Test("A voice in the room does not inflate the measured bleed")
    func ownSpeechDoesNotInflateTheGain() throws {
        let system = speech(200, level: 0.01)
        var microphone = heard(system, gain: 0.001, lag: 0)
        // Somebody in the room speaks over a tenth of it, 20 dB louder than
        // the bleed. Averaged in, that would put the estimate far too high and
        // the gate would start eating speech.
        for index in 80..<100 { microphone[index] = 0.001 }

        let coupling = try #require(
            BleedSuppression.coupling(microphone: microphone, system: system)
        )
        #expect(coupling.decibels < -25)
        #expect(coupling.decibels > -35)
    }

    // MARK: - Gating

    @Test("Frames holding nothing but the call are silenced")
    func bleedOnlyFramesAreGated() throws {
        let system = speech(80, level: 0.01)
        let microphone = heard(system, gain: 0.001, lag: 0)
        let coupling = try #require(
            BleedSuppression.coupling(microphone: microphone, system: system)
        )

        let gate = BleedSuppression.gate(
            microphone: microphone,
            system: system,
            coupling: coupling
        )
        #expect(gate.allSatisfy { $0 })
    }

    @Test("A voice in the room survives the call being loud at the same time")
    func doubleTalkIsKept() {
        let system = speech(60, level: 0.01)
        var microphone = heard(system, gain: 0.001, lag: 0)
        for index in 20..<40 { microphone[index] = 0.01 }   // 30 dB over the bleed

        let gate = BleedSuppression.gate(
            microphone: microphone,
            system: system,
            coupling: .init(lag: 0, gain: 0.001, evidence: 0.9, noiseDecibels: -80)
        )
        #expect(gate[0..<20].allSatisfy { $0 })
        #expect(gate[20..<40].allSatisfy { !$0 })
        #expect(gate[40..<60].allSatisfy { $0 })
    }

    @Test("The gate follows the lag rather than the frame number")
    func gateUsesTheLag() {
        var system = [Float](repeating: 0, count: 20)
        system[5] = 0.01
        var microphone = [Float](repeating: Self.noise, count: 20)
        microphone[8] = 0.01 * 0.001            // the same burst, three frames late
        microphone[12] = 0.01                   // and a word in the room, explained by nothing

        let gate = BleedSuppression.gate(
            microphone: microphone,
            system: system,
            coupling: .init(lag: 3, gain: 0.001, evidence: 0.9, noiseDecibels: -80)
        )
        #expect(gate[8])
        #expect(!gate[12])
    }
}
