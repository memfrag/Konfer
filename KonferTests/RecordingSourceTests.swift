//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import AVFoundation
import Accelerate
import Foundation
@testable import Konfer

/// Exercises a real capture route against real hardware.
///
/// Skipped unless `KONFER_RECORD_APP` names an application that is currently
/// playing audio, because that is the only condition under which a process tap
/// has anything to capture:
///
///     KONFER_RECORD_APP="QuickTime Player" \
///       xcodebuild test -scheme "Konfer (Debug)" \
///       -destination 'platform=macOS,arch=arm64' \
///       -only-testing:KonferTests/RecordingSourceTests
///
@MainActor
struct RecordingSourceTests {

    nonisolated static var targetApplication: String? {
        ProcessInfo.processInfo.environment["KONFER_RECORD_APP"]
    }

    @Test(
        "An app's audio lands on the right channel and the microphone on the left",
        .enabled(if: RecordingSourceTests.targetApplication != nil),
        .timeLimit(.minutes(1))
    )
    func recordsApplicationAudio() async throws {
        let name = try #require(Self.targetApplication)
        let applications = AudioApplications.playingAudio()
        print("  apps playing audio: \(applications.map(\.name))")

        let application = try #require(
            applications.first { $0.name.localizedCaseInsensitiveContains(name) },
            "\(name) isn't playing audio — start playback first"
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("konfer-tap-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        let recorder = AggregateDeviceRecorder()
        let writer = try TwoChannelWriter(url: url)

        try await recorder.prepare(
            RecordingConfiguration(
                microphoneID: AudioInputDevices.available().first?.id,
                systemAudio: .app(application),
                outputURL: url
            )
        )
        try await recorder.start(writingTo: writer)
        try await Task.sleep(for: .seconds(5))
        await recorder.stop()
        writer.finish()

        let levels = try Self.channelLevels(of: url)
        print(String(
            format: "  left(mic) peak %.4f   right(%@) peak %.4f",
            levels.left, application.name, levels.right
        ))

        // The point of the whole design: the app's audio has to be on its own
        // channel, not summed with the room.
        #expect(levels.right > 0.001, "no audio captured from \(application.name)")
    }

    /// Peak level of each channel of a recording.
    nonisolated static func channelLevels(of url: URL) throws -> (left: Float, right: Float) {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)

        let frames = Int(buffer.frameLength)
        guard frames > 0, let channels = buffer.floatChannelData else { return (0, 0) }
        var left: Float = 0
        var right: Float = 0
        vDSP_maxmgv(channels[0], 1, &left, vDSP_Length(frames))
        vDSP_maxmgv(channels[1], 1, &right, vDSP_Length(frames))
        return (left, right)
    }
}
