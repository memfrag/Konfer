//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The queue runs against a stubbed translator: what is worth testing is when
/// lines reach the library and what a cancel leaves behind, and neither needs
/// Apple's language packs — which a test machine may not have, and which take
/// a third of a second a line when it does.

/// A translator that answers instantly and remembers what it was asked for.
///
/// `nonisolated` because the queue calls it through `@Sendable` closures; the
/// app builds with default-`MainActor` isolation, so a nested type would
/// otherwise inherit it and refuse to be called from them.
private nonisolated final class Stub: @unchecked Sendable {

    var availability: TranslationAvailability = .ready

    /// The turns it was handed, in order.
    var received: [Utterance] = []

    /// How many lines to hand back at a time.
    var chunk = 1

    /// Throws after this many lines, for a run that dies halfway.
    var failAfter: Int?

    /// Holds the run open, so a test can observe a queue mid-flight.
    var blocked = false

    struct Failure: Error {}

    func translator() -> TranslationQueue.Translator {
        TranslationQueue.Translator(
            availability: { [self] _, _ in availability },
            translate: { [self] utterances, _, _, onLines in
                received = utterances
                var pending: [TranslatedLine] = []
                for (index, utterance) in utterances.enumerated() {
                    while blocked, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(1))
                    }
                    if Task.isCancelled {
                        if !pending.isEmpty { onLines(pending) }
                        throw TranscriptTranslationError.cancelled
                    }
                    if let failAfter, index >= failAfter {
                        if !pending.isEmpty { onLines(pending) }
                        throw Failure()
                    }
                    pending.append(
                        TranslatedLine(utteranceID: utterance.id, text: "EN:\(utterance.text)")
                    )
                    if pending.count >= chunk {
                        onLines(pending)
                        pending = []
                    }
                }
                if !pending.isEmpty { onLines(pending) }
            }
        )
    }
}

@MainActor
struct TranslationQueueTests {

    // MARK: - Fixtures

    private func makeStore() -> MeetingStore {
        MeetingStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("KonferTranslationQueueTests-\(UUID().uuidString)")
        )
    }

    private func makeMeeting(turns: Int = 4) -> Meeting {
        Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 600,
            importedAt: Date(),
            language: .swedish,
            speakers: [SpeakerLabel(id: "A", name: "Anna")],
            utterances: (0..<turns).map {
                Utterance(
                    speakerId: "A",
                    start: Double($0) * 10,
                    end: Double($0) * 10 + 5,
                    text: "Mening \($0)."
                )
            }
        )
    }

    /// Waits for the queue to leave `.translating`, so a test need not guess.
    private func settle(_ queue: TranslationQueue) async {
        for _ in 0..<2000 where queue.state.isTranslating {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - The happy path

    @Test("A queue with nothing running is idle")
    func startsIdle() {
        let queue = TranslationQueue(meetingStore: makeStore(), translator: Stub().translator())

        #expect(queue.state == .idle)
        #expect(queue.title == nil)
    }

    @Test("A finished translation reaches the library, line for line")
    func writesThrough() async throws {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let queue = TranslationQueue(meetingStore: store, translator: Stub().translator())

        queue.translate(meeting, into: .english)
        await settle(queue)

        let stored = try #require(store.meeting(meeting.id))
        #expect(stored.translation?.target == .english)
        #expect(stored.translation?.lines.count == 4)
        #expect(stored.translatedText(for: meeting.utterances[0]) == "EN:Mening 0.")
        #expect(queue.state == .finished(lines: 4, target: .english))
    }

    @Test("Progress counts finished turns against the number sent")
    func reportsProgress() async throws {
        let store = makeStore()
        let meeting = makeMeeting(turns: 10)
        store.add(meeting)
        let stub = Stub()
        stub.blocked = true
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        #expect(queue.state == .translating(done: 0, total: 10))
        #expect(queue.state.fraction == 0)

        stub.blocked = false
        await settle(queue)

        #expect(queue.state == .finished(lines: 10, target: .english))
    }

    @Test("Turns reach the library as they arrive, not only at the end")
    func writesThroughInChunks() async throws {
        let store = makeStore()
        let meeting = makeMeeting(turns: 6)
        store.add(meeting)
        let stub = Stub()
        stub.failAfter = 3
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        await settle(queue)

        // The run died at the fourth turn; the first three are still there.
        let stored = try #require(store.meeting(meeting.id))
        #expect(stored.translation?.lines.count == 3)
        #expect(queue.state != .idle)
    }

    // MARK: - Cancelling

    @Test("Cancelling keeps the turns already translated and reports no failure")
    func cancellingKeepsWhatWasDone() async throws {
        let store = makeStore()
        let meeting = makeMeeting(turns: 8)
        store.add(meeting)
        let stub = Stub()
        stub.blocked = true
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        queue.cancel()
        stub.blocked = false
        await settle(queue)

        #expect(queue.state == .idle)
        let stored = try #require(store.meeting(meeting.id))
        #expect(stored.translation?.target == .english)
    }

    // MARK: - Refusals

    @Test("A second translation is refused while one is running")
    func oneAtATime() async {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let stub = Stub()
        stub.blocked = true
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        queue.translate(meeting, into: .german)

        #expect(queue.state == .translating(done: 0, total: 4))
        stub.blocked = false
        await settle(queue)
        #expect(queue.state == .finished(lines: 4, target: .english))
    }

    @Test("Translating a meeting into its own language is refused")
    func refusesSameLanguage() {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let queue = TranslationQueue(meetingStore: store, translator: Stub().translator())

        queue.translate(meeting, into: .swedish)

        #expect(queue.state == .failed(TranslationQueueTests.message(for: .sameLanguage)))
    }

    @Test("A pair Konfer knows macOS refuses fails without asking the framework")
    func refusesUnavailablePairWithoutAsking() {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let stub = Stub()
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .polish)

        #expect(queue.state.isTranslating == false)
        #expect(stub.received.isEmpty)
    }

    @Test("A pair that needs a language pack fails before a single turn is sent")
    func refusesUninstalledPair() async {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let stub = Stub()
        stub.availability = .needsDownload
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        await settle(queue)

        #expect(stub.received.isEmpty)
        #expect(queue.state == .failed(
            TranslationQueueTests.message(for: .notInstalled(from: .swedish, to: .english))
        ))
    }

    @Test("A failure stays on screen until it is acknowledged")
    func failureNeedsDismissing() {
        let store = makeStore()
        let meeting = makeMeeting()
        store.add(meeting)
        let queue = TranslationQueue(meetingStore: store, translator: Stub().translator())

        queue.translate(meeting, into: .swedish)
        #expect(queue.state != .idle)

        queue.acknowledge()
        #expect(queue.state == .idle)
    }

    // MARK: - Filling gaps

    @Test("Translating the rest sends only the turns that have no translation")
    func fillsGapsOnly() async throws {
        let store = makeStore()
        var meeting = makeMeeting(turns: 4)
        meeting.translation = TranscriptTranslation(
            target: .english,
            lines: [
                TranslatedLine(utteranceID: meeting.utterances[0].id, text: "Kept."),
                TranslatedLine(utteranceID: meeting.utterances[1].id, text: "Also kept.")
            ]
        )
        store.add(meeting)
        let stub = Stub()
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english, fillingGaps: true)
        await settle(queue)

        #expect(stub.received.count == 2)
        let stored = try #require(store.meeting(meeting.id))
        #expect(stored.translation?.lines.count == 4)
        #expect(stored.translatedText(for: meeting.utterances[0]) == "Kept.")
        #expect(stored.translatedText(for: meeting.utterances[3]) == "EN:Mening 3.")
    }

    @Test("Choosing a different language starts over rather than mixing two")
    func newTargetStartsOver() async throws {
        let store = makeStore()
        var meeting = makeMeeting(turns: 3)
        meeting.translation = TranscriptTranslation(
            target: .english,
            lines: [TranslatedLine(utteranceID: meeting.utterances[0].id, text: "Old.")]
        )
        store.add(meeting)
        let stub = Stub()
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .german, fillingGaps: true)
        await settle(queue)

        let stored = try #require(store.meeting(meeting.id))
        #expect(stored.translation?.target == .german)
        #expect(stored.translation?.lines.count == 3)
        #expect(stored.translatedText(for: meeting.utterances[0]) == "EN:Mening 0.")
    }

    @Test("A meeting with nothing left to translate finishes without sending anything")
    func nothingToDo() async {
        let store = makeStore()
        var meeting = makeMeeting(turns: 2)
        meeting.translation = TranscriptTranslation(
            target: .english,
            lines: meeting.utterances.map { TranslatedLine(utteranceID: $0.id, text: "Done.") }
        )
        store.add(meeting)
        let stub = Stub()
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english, fillingGaps: true)

        #expect(stub.received.isEmpty)
        #expect(queue.state == .finished(lines: 0, target: .english))
    }

    @Test("Empty turns are never sent")
    func skipsEmptyTurns() async {
        let store = makeStore()
        var meeting = makeMeeting(turns: 2)
        meeting.utterances.append(
            Utterance(speakerId: "A", start: 90, end: 91, text: "   ")
        )
        store.add(meeting)
        let stub = Stub()
        let queue = TranslationQueue(meetingStore: store, translator: stub.translator())

        queue.translate(meeting, into: .english)
        await settle(queue)

        #expect(stub.received.count == 2)
    }

    // MARK: - Helper

    private static func message(for error: TranscriptTranslationError) -> String {
        [error.errorDescription, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
