//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The one suite that needs Apple's language packs, and so the one that is
/// skipped by default — a test machine may have none installed, and a run
/// against real models costs a third of a second a line.
///
/// ```sh
/// TEST_RUNNER_KONFER_TRANSLATION=real \
///   xcodebuild test -scheme "Konfer (Debug)" \
///   -destination 'platform=macOS,arch=arm64' \
///   -only-testing:KonferTests/TranslationAvailabilityTests
/// ```
///
/// It exists to check the two claims the rest of the tests take on trust:
/// that the pair table still matches what macOS reports, and that the
/// headless session translates at all.
struct TranslationAvailabilityTests {

    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["KONFER_TRANSLATION"] == "real"
    }

    @Test(
        "What macOS reports still matches the pairs Konfer refuses",
        .enabled(if: TranslationAvailabilityTests.isEnabled)
    )
    func tableMatchesTheFramework() async throws {
        for source in MeetingLanguage.allCases {
            for target in MeetingLanguage.allCases where target != source {
                let live = await TranscriptTranslator.availability(from: source, to: target)
                let recorded = TranslationSupport.isKnownUnavailable(from: source, to: target)

                let says = recorded ? "unavailable" : "available"
                #expect(
                    (live == .unavailable) == recorded,
                    "\(source.code)->\(target.code): macOS says \(live), table says \(says)"
                )
            }
        }
    }

    @Test(
        "A meeting's turns come back translated, each on its own line",
        .enabled(if: TranslationAvailabilityTests.isEnabled)
    )
    func translatesRealTurns() async throws {
        try #require(
            await TranscriptTranslator.availability(from: .swedish, to: .english) == .ready,
            "Swedish to English is not installed on this Mac"
        )

        let utterances = [
            Utterance(speakerId: "A", start: 0, end: 3, text: "Hej allihopa och välkomna."),
            Utterance(speakerId: "B", start: 4, end: 7, text: "Vi börjar med budgeten."),
            Utterance(speakerId: "A", start: 8, end: 9, text: "Okej.")
        ]

        let collected = Collector()
        try await TranscriptTranslator().translate(
            utterances, from: .swedish, to: .english
        ) { collected.append($0) }

        let lines = collected.lines
        #expect(lines.count == utterances.count)
        for utterance in utterances {
            let line = lines.first { $0.utteranceID == utterance.id }
            #expect(line != nil, "no line came back for \(utterance.text)")
            #expect(line?.text.isEmpty == false)
            #expect(line?.text != utterance.text, "\(utterance.text) came back untranslated")
        }
    }

    @Test(
        "A pair macOS has no path for is refused before a session is made",
        .enabled(if: TranslationAvailabilityTests.isEnabled)
    )
    func refusesUnavailablePair() async throws {
        #expect(
            await TranscriptTranslator.availability(from: .swedish, to: .polish) == .unavailable
        )
    }
}

/// A box for lines arriving from the translator's `@Sendable` callback.
private nonisolated final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TranslatedLine] = []

    func append(_ lines: [TranslatedLine]) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(contentsOf: lines)
    }

    var lines: [TranslatedLine] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
