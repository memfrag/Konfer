//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AVFoundation
import Observation
import SwiftUI

/// Plays the original recording, in step with the transcript.
///
/// Plays the user's own file rather than the 16 kHz mono conversion the models
/// consume — that one is downsampled for machines, not ears. `AVPlayer` rather
/// than `AVAudioPlayer` because a source recording may be a video file.
@Observable @MainActor
final class PlayerController {

    private(set) var currentTime: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var isLoaded = false

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var observer: Any?

    func load(_ url: URL) {
        unload()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let player = AVPlayer(url: url)
        self.player = player
        isLoaded = true

        // 20 ticks a second is enough to look continuous without making the
        // main actor do needless work during an hour-long recording.
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
        }
    }

    func unload() {
        if let observer, let player {
            player.removeTimeObserver(observer)
        }
        observer = nil
        player?.pause()
        player = nil
        isPlaying = false
        isLoaded = false
        currentTime = 0
    }

    func playPause() {
        guard let player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
    }

    /// Moves the playhead, never landing before the moment asked for.
    ///
    /// `CMTime(seconds:preferredTimescale:)` rounds to the nearest tick, and at
    /// 600 ticks a second that put nearly a third of word starts up to 0.8 ms
    /// *early*. Word timings are contiguous — one word's end is the next word's
    /// start — so landing early means landing inside the previous word, which
    /// is what made clicking a word highlight the one before it. Rounding up at
    /// a fine timescale keeps the playhead inside the word that was clicked.
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let target = max(0, time)
        currentTime = target
        player.seek(
            to: Self.seekTime(for: target),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// The playhead position for a moment, never earlier than the moment itself.
    ///
    /// Rounds up, because rounding to the nearest tick is what caused the bug
    /// this exists to prevent: measured across three real transcripts, 28.8% of
    /// word starts landed up to 0.8 ms early at 600 ticks a second.
    nonisolated static func seekTime(for time: TimeInterval) -> CMTime {
        CMTime(
            value: Int64((max(0, time) * Double(timescale)).rounded(.up)),
            timescale: timescale
        )
    }

    /// Fine enough that rounding up overshoots by at most 23 microseconds.
    nonisolated static let timescale: CMTimeScale = 44_100
}
