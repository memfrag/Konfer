//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Accelerate
import Foundation

/// Writes a recording with the microphone on channel 0 and system audio on
/// channel 1.
///
/// Apple Lossless rather than AAC, deliberately. AAC's stereo coding can
/// predict one channel from the other, which is a sensible thing to do to a
/// stereo image and a destructive thing to do to two unrelated sources — it
/// would quietly blur the separation this whole design exists to preserve.
///
/// The two sides arrive independently and at their own pace, so each is queued
/// and a frame is only written once both have delivered it. A side that never
/// delivers becomes silence rather than a stall: a missing microphone should
/// give a quiet left channel, not a recording that hangs.
nonisolated final class TwoChannelWriter: @unchecked Sendable {

    /// Everything is resampled to this before writing, so the two sides agree
    /// regardless of what their devices run at.
    static let sampleRate: Double = 48_000

    private let lock = NSLock()
    /// Released by `finish()`. An `.m4a` is only a valid file once its
    /// container has been finalised, which `AVAudioFile` does when it is
    /// deallocated — so this has to be let go before anyone reads the
    /// recording, not merely stopped.
    private var file: AVAudioFile?
    private let format: AVAudioFormat

    private var microphone: [Float] = []
    private var system: [Float] = []

    /// Peak level per channel since the last read, for the meters.
    private var microphonePeak: Float = 0
    private var systemPeak: Float = 0

    private(set) var framesWritten: AVAudioFramePosition = 0

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitDepthHintKey: 16,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            throw RecordingError.noAudioDevice
        }
        self.format = format
        startWriting()
    }

    // MARK: - Writer thread

    private var isWriting = true

    /// Drains the queues on its own thread, off whatever realtime thread the
    /// samples arrived on.
    private func startWriting() {
        let thread = Thread { [weak self] in
            while let self, self.isWriting {
                self.drain()
                // Long enough that a wake-up is worth it, short enough that the
                // queues stay small: at 48 kHz this is about 2400 frames.
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "pizza.martin.Konfer.recording-writer"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    // MARK: - Input

    /// Called from Core Audio's realtime thread, so it only enqueues.
    ///
    /// Encoding lossless audio and writing it to disk takes far longer than a
    /// render callback is allowed to take; doing it here deadlocks the audio
    /// unit and the recording stops dead. A writer thread does that instead.
    func appendMicrophone(_ samples: [Float]) {
        lock.lock()
        microphone.append(contentsOf: samples)
        microphonePeak = max(microphonePeak, Self.peak(of: samples))
        lock.unlock()
    }

    func appendSystemAudio(_ samples: [Float]) {
        lock.lock()
        system.append(contentsOf: samples)
        systemPeak = max(systemPeak, Self.peak(of: samples))
        lock.unlock()
    }

    /// Marks a side as never going to deliver, so the other isn't held up
    /// waiting for it.
    func markSilent(_ channel: Channel) {
        lock.lock()
        switch channel {
        case .microphone: silentChannels.insert(.microphone)
        case .system: silentChannels.insert(.system)
        }
        lock.unlock()
    }

    enum Channel: Hashable { case microphone, system }
    private var silentChannels: Set<Channel> = []

    // MARK: - Levels

    /// Peak level per channel since the previous call, 0...1.
    func consumeLevels() -> (microphone: Float, system: Float) {
        lock.lock()
        defer {
            microphonePeak = 0
            systemPeak = 0
            lock.unlock()
        }
        return (microphonePeak, systemPeak)
    }

    // MARK: - Output

    /// Writes whatever both sides have both delivered.
    private func drain() {
        lock.lock()

        // A silent side is treated as having delivered silence forever, so it
        // never becomes the thing holding up the recording.
        if silentChannels.contains(.microphone), system.count > microphone.count {
            microphone.append(contentsOf: [Float](repeating: 0, count: system.count - microphone.count))
        }
        if silentChannels.contains(.system), microphone.count > system.count {
            system.append(contentsOf: [Float](repeating: 0, count: microphone.count - system.count))
        }

        let ready = min(microphone.count, system.count)
        guard ready > 0 else { return lock.unlock() }

        let left = Array(microphone.prefix(ready))
        let right = Array(system.prefix(ready))
        microphone.removeFirst(ready)
        system.removeFirst(ready)
        lock.unlock()

        write(left: left, right: right)
    }

    private func write(left: [Float], right: [Float]) {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(left.count)
        ), let channels = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: left.count) }
        right.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: right.count) }

        do {
            try file?.write(from: buffer)
            framesWritten += AVAudioFramePosition(left.count)
        } catch {
            // Losing a buffer is bad but stopping the recording mid-meeting is
            // worse; the meters will show it if this becomes persistent.
        }
    }

    /// Flushes whatever is left, padding the shorter side with silence, then
    /// closes the file so it can be read.
    func finish() {
        lock.lock()
        let length = max(microphone.count, system.count)
        if length > 0 {
            microphone.append(contentsOf: [Float](repeating: 0, count: length - microphone.count))
            system.append(contentsOf: [Float](repeating: 0, count: length - system.count))
        }
        lock.unlock()

        // Stop the writer thread first, then flush what's left on this one, so
        // nothing is being written while the file is closed.
        isWriting = false
        Thread.sleep(forTimeInterval: 0.08)
        drain()

        lock.lock()
        file = nil
        lock.unlock()
    }

    // MARK: - Helpers

    /// vDSP rather than a Swift loop: this runs on every captured buffer for
    /// the whole recording, and a bounds-checked loop is about a hundred times
    /// slower in a debug build (see `WaveformStore`).
    private static func peak(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return peak
    }
}
