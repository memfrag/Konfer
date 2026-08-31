//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Times the real waveform path, cold and warm.
///
/// Skipped unless `KONFER_AUDIO` names a recording.
@MainActor
struct WaveformTimingTests {

    nonisolated static var audioURL: URL? {
        ProcessInfo.processInfo.environment["KONFER_AUDIO"]
            .map { URL(fileURLWithPath: $0) }
    }

    @Test(
        "Waveform computation and cache timing",
        .enabled(if: WaveformTimingTests.audioURL != nil),
        .timeLimit(.minutes(10))
    )
    func timing() async throws {
        let url = try #require(Self.audioURL)
        let id = UUID()
        defer { WaveformStore.removeCache(for: id) }

        let coldStart = Date()
        let cold = await WaveformStore.waveform(for: id, audio: url)
        let coldSeconds = Date().timeIntervalSince(coldStart)

        let warmStart = Date()
        let warm = await WaveformStore.waveform(for: id, audio: url)
        let warmSeconds = Date().timeIntervalSince(warmStart)

        print(String(
            format: "  cold %.2fs, warm %.2fs, %d buckets",
            coldSeconds, warmSeconds, cold?.peaks.count ?? 0
        ))

        #expect(cold != nil)
        #expect(warm?.peaks.count == cold?.peaks.count)
    }
}
