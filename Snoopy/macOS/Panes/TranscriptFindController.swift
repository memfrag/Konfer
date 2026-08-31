//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation
import SwiftUI

/// The state of a find session in one transcript.
///
/// Separate from the pane because the Edit menu has to reach it: ⌘F and ⌘G are
/// menu commands, and a `Commands` block can only see what a focused view
/// publishes. See ``FindCommands``.
@Observable @MainActor
final class TranscriptFindController {

    // MARK: - What the user typed

    var isPresented = false

    var query = "" {
        didSet { if query != oldValue { recompute() } }
    }

    var replacement = ""

    // MARK: - What was found

    private(set) var matches: [TranscriptMatch] = []

    /// Index into ``matches``. Kept in range by everything that changes them.
    private(set) var currentIndex = 0

    var current: TranscriptMatch? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    var hasMatches: Bool { !matches.isEmpty }

    /// "3 of 17", or the honest alternative.
    var summary: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        guard hasMatches else { return "No matches" }
        return "\(currentIndex + 1) of \(matches.count)"
    }

    // MARK: - The transcript being searched

    @ObservationIgnored private var utterances: [Utterance] = []

    /// Point the session at a transcript, or at a changed one.
    ///
    /// Called whenever the meeting changes, including after a replacement, so
    /// the match list never outlives the text it describes.
    func update(with utterances: [Utterance]) {
        self.utterances = utterances
        recompute()
    }

    private func recompute() {
        let previous = current
        matches = TranscriptSearch.matches(for: query, in: utterances)

        // Stay on the match the user was looking at where it still exists, so
        // replacing one occurrence doesn't throw away their place in the file.
        if let previous,
           let index = matches.firstIndex(where: {
               $0.utteranceID == previous.utteranceID && $0.offset == previous.offset
           }) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, max(matches.count - 1, 0))
        }
    }

    // MARK: - Moving through the matches

    /// Wraps, because a find bar that stops at the last match makes you reach
    /// for the mouse to start again.
    func next() {
        guard hasMatches else { return }
        currentIndex = (currentIndex + 1) % matches.count
    }

    func previous() {
        guard hasMatches else { return }
        currentIndex = (currentIndex + matches.count - 1) % matches.count
    }

    // MARK: - Opening and closing

    func present() {
        isPresented = true
    }

    func dismiss() {
        isPresented = false
    }

    // MARK: - What a replacement would cost

    /// How many of the current matches would lose their turn's word timings.
    ///
    /// Shown before Replace All runs, because those timings cannot be got back
    /// without transcribing the recording again.
    func matchesThatWouldDropTimings() -> Int {
        var byID: [UUID: Utterance] = [:]
        for utterance in utterances { byID[utterance.id] = utterance }

        return matches.count {
            guard let utterance = byID[$0.utteranceID] else { return false }
            return TranscriptSearch.replacementKind(of: $0, in: utterance) == .dropsTimings
        }
    }
}

// MARK: - Focused value

/// Lets the Edit menu drive the find bar of whichever transcript is focused.
struct TranscriptFindKey: FocusedValueKey {
    typealias Value = TranscriptFindController
}

extension FocusedValues {
    var transcriptFind: TranscriptFindController? {
        get { self[TranscriptFindKey.self] }
        set { self[TranscriptFindKey.self] = newValue }
    }
}
