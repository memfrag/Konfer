//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// Runs one meeting's translation at a time, and says how it is going.
///
/// Modelled on ``VideoExportQueue``, and here for the same reason: two minutes
/// of work has to outlive the pane that started it. Someone who asks for a
/// translation and then goes to read another transcript should not silently
/// cancel their own translation by navigating away.
///
/// It differs from that queue in one deliberate way. A cancelled video export
/// deletes its half-written file, because half a movie is unplayable. Half a
/// translation is genuinely half a translation: the pane shows the original for
/// every turn that has none, so lines are written through as they arrive and
/// cancelling keeps them. "Translate the Rest" then costs only the turns that
/// are missing.
@Observable @MainActor
final class TranslationQueue {

    // MARK: - Dependencies

    /// How the queue reaches Apple's translator.
    ///
    /// Injected for the same reason ``ModelDownloadQueue/Fetcher`` is: the
    /// state machine is the part worth testing, and no test should need a
    /// language pack installed to run one.
    struct Translator: Sendable {

        var availability: @Sendable (
            MeetingLanguage, MeetingLanguage
        ) async -> TranslationAvailability

        var translate: @Sendable (
            [Utterance], MeetingLanguage, MeetingLanguage,
            @Sendable @escaping ([TranslatedLine]) -> Void
        ) async throws -> Void

        static let live = Translator(
            availability: { source, target in
                await TranscriptTranslator.availability(from: source, to: target)
            },
            translate: { utterances, source, target, onLines in
                try await TranscriptTranslator().translate(
                    utterances, from: source, to: target, onLines: onLines
                )
            }
        )
    }

    // MARK: - State

    enum State: Equatable {
        case idle
        case translating(done: Int, total: Int)
        case finished(lines: Int, target: MeetingLanguage)
        case failed(String)

        var isTranslating: Bool {
            if case .translating = self { return true }
            return false
        }

        var fraction: Double? {
            guard case .translating(let done, let total) = self, total > 0 else { return nil }
            return min(Double(done) / Double(total), 1)
        }
    }

    private(set) var state: State = .idle

    /// The meeting being translated, for the footer to name.
    private(set) var title: String?

    /// Which meeting, so the pane can tell "mine" from "someone else's".
    private(set) var meetingID: UUID?

    /// When it started, for the elapsed clock.
    private(set) var startedAt: Date?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let meetingStore: MeetingStore
    @ObservationIgnored private let translator: Translator

    init(meetingStore: MeetingStore, translator: Translator = .live) {
        self.meetingStore = meetingStore
        self.translator = translator
    }

    // MARK: - Running

    /// Translates a meeting.
    ///
    /// - Parameter fillingGaps: True for "Translate the Rest" — keeps what is
    ///   already there and sends only the turns that have nothing. False starts
    ///   the target over, which is what choosing a different language means.
    func translate(
        _ meeting: Meeting,
        into target: MeetingLanguage,
        fillingGaps: Bool = false
    ) {
        guard !state.isTranslating else { return }

        let source = meeting.language
        guard source != target else {
            fail(TranscriptTranslationError.sameLanguage)
            return
        }

        // Answered from the measured table, so a pair macOS refuses costs
        // nothing to refuse — no framework call, no session, no wait.
        if TranslationSupport.isKnownUnavailable(from: source, to: target) {
            fail(TranscriptTranslationError.pairUnavailable(from: source, to: target))
            return
        }

        let keepingExisting = fillingGaps && meeting.translation?.target == target
        let pending = keepingExisting
            ? meeting.untranslatedKeptUtterances
            : meeting.keptUtterances.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

        guard !pending.isEmpty else {
            state = .finished(lines: 0, target: target)
            title = meeting.title
            meetingID = meeting.id
            return
        }

        let id = meeting.id
        let total = pending.count
        title = meeting.title
        meetingID = id
        startedAt = Date()
        state = .translating(done: 0, total: total)

        if !keepingExisting {
            meetingStore.modify(id) {
                $0.translation = TranscriptTranslation(target: target)
            }
        }

        // Captured once, weakly, rather than inside the run below: a late
        // callback from a cancelled job must not resurrect the bar — the same
        // guard the download and export queues keep.
        let onLines: @Sendable ([TranslatedLine]) -> Void = { [weak self] lines in
            Task { @MainActor in
                guard let self, self.state.isTranslating else { return }
                self.apply(lines, to: id, target: target, of: total)
            }
        }

        task = Task { [weak self, translator] in
            do {
                // Checked before a single request goes out, so "you need to
                // download Polish" arrives in a second rather than a minute.
                switch await translator.availability(source, target) {
                case .ready:
                    break
                case .needsDownload:
                    throw TranscriptTranslationError.notInstalled(from: source, to: target)
                case .unavailable:
                    throw TranscriptTranslationError.pairUnavailable(from: source, to: target)
                }

                try await translator.translate(pending, source, target, onLines)

                await MainActor.run {
                    guard let self, self.state.isTranslating else { return }
                    let done = if case .translating(let done, _) = self.state { done } else { 0 }
                    self.state = .finished(lines: done, target: target)
                    self.startedAt = nil
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    // Cancelling keeps what arrived and says nothing: the user
                    // asked for it to stop, which is not a failure to report.
                    if case TranscriptTranslationError.cancelled = error {
                        self.state = .idle
                        self.startedAt = nil
                        return
                    }
                    self.fail(error)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func acknowledge() {
        guard !state.isTranslating else { return }
        state = .idle
        title = nil
        meetingID = nil
        startedAt = nil
    }

    // MARK: - Writing through

    private func apply(
        _ lines: [TranslatedLine],
        to id: UUID,
        target: MeetingLanguage,
        of total: Int
    ) {
        meetingStore.modify(id) { meeting in
            // The user may have retranscribed or picked another language while
            // this was in flight; the lines belong to neither.
            guard meeting.translation?.target == target else { return }

            let replaced = Set(lines.map(\.utteranceID))
            meeting.translation?.lines.removeAll { replaced.contains($0.utteranceID) }
            meeting.translation?.lines.append(contentsOf: lines)
            meeting.translation?.translatedAt = Date()
        }

        guard case .translating(let done, _) = state else { return }
        state = .translating(done: min(done + lines.count, total), total: total)
    }

    private func fail(_ error: Error) {
        state = .failed(Self.describe(error))
        startedAt = nil
    }

    private static func describe(_ error: Error) -> String {
        guard let translation = error as? TranscriptTranslationError else {
            return error.localizedDescription
        }
        return [translation.errorDescription, translation.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
