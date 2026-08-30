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

    func seek(to time: TimeInterval) {
        guard let player else { return }
        currentTime = time
        player.seek(
            to: CMTime(seconds: max(0, time), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }
}
