//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import AVFoundation
@testable import Snoopy

/// Clicking a word seeks to its start, and the playhead must not land before
/// it.
///
/// Word timings abut — one word's end is the next word's start for 85–95% of
/// adjacent pairs in real transcripts — so a playhead a fraction early sits
/// inside the *previous* word, and that word highlights instead. This is what
/// made clicking a word highlight the one before it.
@MainActor
struct PlayerSeekTests {

    /// Word starts that `CMTime(seconds:preferredTimescale: 600)` rounds down.
    private let awkwardTimes: [TimeInterval] = [
        1.7383, 12.3456, 0.0009, 59.9992, 3.7781, 1234.5671, 7.00083,
    ]

    @Test("Seeking never lands before the moment asked for")
    func seekNeverUndershoots() {
        for time in awkwardTimes {
            let landed = CMTimeGetSeconds(PlayerController.seekTime(for: time))
            #expect(landed >= time, "seeking to \(time) landed at \(landed)")
        }
    }

    @Test("Rounding to the nearest tick would have landed early")
    func nearestTickRoundingUndershoots() {
        // The old behaviour, kept as the reason the code above rounds up.
        let undershoots = awkwardTimes.filter {
            CMTimeGetSeconds(CMTime(seconds: $0, preferredTimescale: 600)) < $0
        }
        #expect(!undershoots.isEmpty)
    }

    @Test("The playhead lands close enough to be the same moment")
    func seekIsAccurate() {
        for time in awkwardTimes {
            let landed = CMTimeGetSeconds(PlayerController.seekTime(for: time))
            #expect(landed - time < 0.001)
        }
    }

    @Test("A negative time is clamped rather than seeking backwards")
    func negativeTimeIsClamped() {
        #expect(CMTimeGetSeconds(PlayerController.seekTime(for: -5)) == 0)
    }

    @Test("A word clicked at a rounded-down boundary still highlights itself")
    func clickedWordWinsAfterQuantisation() {
        // The end-to-end shape of the bug: contiguous words, a click on the
        // second one, and the playhead wherever the seek actually lands.
        let words = [
            WordSpan(word: "one", start: 0, end: 12.3456),
            WordSpan(word: "two", start: 12.3456, end: 13.0),
        ]
        let landed = CMTimeGetSeconds(PlayerController.seekTime(for: words[1].start))
        #expect(WordToken.activeIndex(in: words, at: landed) == 1)
    }
}
