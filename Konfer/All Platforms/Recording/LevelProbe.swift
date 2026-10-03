//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// An ``AudioSink`` that keeps nothing but the peaks, for the meters before a
/// recording starts.
///
/// Fed by the same ``RecordingSource`` the recording would use rather than by
/// a microphone opened on the side, so a meter that moves here is evidence the
/// recording will hear the same thing — including a tap macOS has quietly
/// refused, which shows up as a flat right-hand bar while there is still time
/// to fix it.
nonisolated final class LevelProbe: AudioSink, @unchecked Sendable {

    private let lock = NSLock()
    private var microphonePeak: Float = 0
    private var systemPeak: Float = 0

    func appendMicrophone(_ samples: [Float]) {
        let peak = TwoChannelWriter.peak(of: samples)
        lock.lock()
        microphonePeak = max(microphonePeak, peak)
        lock.unlock()
    }

    func appendSystemAudio(_ samples: [Float]) {
        let peak = TwoChannelWriter.peak(of: samples)
        lock.lock()
        systemPeak = max(systemPeak, peak)
        lock.unlock()
    }

    func consumeLevels() -> (microphone: Float, system: Float) {
        lock.lock()
        defer {
            microphonePeak = 0
            systemPeak = 0
            lock.unlock()
        }
        return (microphonePeak, systemPeak)
    }
}
