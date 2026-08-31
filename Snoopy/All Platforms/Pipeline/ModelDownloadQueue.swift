//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// Downloads models on purpose, rather than as a side effect of transcribing.
///
/// Models used to arrive mid-run, which meant a user who picked Polish
/// discovered three gigabytes after committing to a transcription. Here they
/// are asked for: on first launch, or from Settings, and the run itself now
/// refuses to start without them.
///
/// One download at a time. Two three-gigabyte fetches over one connection take
/// the same total time as one after the other, but finish *both* late — and a
/// queue that finishes its first item early is a queue you can start
/// transcribing against sooner.
///
@Observable @MainActor
final class ModelDownloadQueue {

    // MARK: - Types

    /// How the queue reaches the disk and the network.
    ///
    /// Injected so the ordering and failure handling can be tested without
    /// downloading three gigabytes: the state machine here is the part worth
    /// testing, and the fetching itself belongs to FluidAudio and WhisperKit.
    struct Fetcher: Sendable {
        var isInstalled: @Sendable (ManagedModel) -> Bool
        var download: @Sendable (ManagedModel, @escaping @Sendable (Double) -> Void) async throws -> Void
        var remove: @Sendable (ManagedModel) throws -> Void

        static let live = Fetcher(
            isInstalled: { $0.isInstalled },
            download: { try await $0.download(progress: $1) },
            remove: { try $0.remove() }
        )
    }

    enum State: Equatable {
        case notInstalled
        case queued
        case downloading(Double)
        case installed
        /// Kept as a message rather than an `Error` so the row can show it and
        /// the user can retry without the failure disappearing.
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .queued, .downloading: true
            case .notInstalled, .installed, .failed: false
            }
        }
    }

    // MARK: - Observable state

    /// Every model Snoopy manages, in a fixed order, with what we know about it.
    private(set) var states: [ManagedModel: State] = [:]

    private(set) var active: ManagedModel?

    /// Models still waiting, in the order they will run.
    private(set) var pending: [ManagedModel] = []

    var isRunning: Bool { active != nil }

    /// What the whole queue has left to fetch, for a summary line.
    var remainingBytes: Int64 {
        ([active].compactMap { $0 } + pending)
            .reduce(0) { $0 + $1.estimatedBytes }
    }

    // MARK: - Private

    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let fetcher: Fetcher

    init(fetcher: Fetcher = .live) {
        self.fetcher = fetcher
        refresh()
    }

    // MARK: - Reading the disk

    /// Re-reads what is actually on disk, for every model that isn't busy.
    ///
    /// Cheap enough to call whenever a window appears: three directory checks.
    func refresh() {
        for model in ManagedModel.allCases where states[model]?.isBusy != true {
            states[model] = fetcher.isInstalled(model) ? .installed : .notInstalled
        }
    }

    func state(of model: ManagedModel) -> State {
        states[model] ?? .notInstalled
    }

    // MARK: - Queueing

    /// Queues a model unless it is already installed or on its way.
    func enqueue(_ model: ManagedModel) {
        guard state(of: model) != .installed,
              !state(of: model).isBusy else { return }
        states[model] = .queued
        pending.append(model)
        startNextIfIdle()
    }

    /// Queues everything the given languages need, plus diarization, which
    /// every transcription uses whatever the language.
    ///
    /// Languages Apple covers contribute nothing — which is itself the useful
    /// signal on the first-run screen.
    func enqueueEverythingNeeded(for languages: [MeetingLanguage]) {
        enqueue(.diarization)
        for model in languages.compactMap(ManagedModel.init(transcribing:)) {
            enqueue(model)
        }
    }

    /// Abandons the running download and empties the queue. Whatever had
    /// already finished stays on disk.
    func cancelAll() {
        pending.removeAll()
        runTask?.cancel()
    }

    func remove(_ model: ManagedModel) throws {
        try fetcher.remove(model)
        states[model] = .notInstalled
    }

    // MARK: - Running

    private func startNextIfIdle() {
        guard active == nil, !pending.isEmpty else { return }
        let model = pending.removeFirst()
        active = model
        states[model] = .downloading(0)

        runTask = Task { [weak self] in
            await self?.run(model)
            self?.finish()
        }
    }

    private func run(_ model: ManagedModel) async {
        do {
            try await fetcher.download(model) { [weak self] fraction in
                Task { @MainActor in
                    // A late progress callback from a cancelled download must
                    // not resurrect the row.
                    guard self?.active == model else { return }
                    self?.states[model] = .downloading(fraction)
                }
            }
            states[model] = fetcher.isInstalled(model)
                ? .installed
                : .failed("The download finished incomplete.")
        } catch is CancellationError {
            states[model] = fetcher.isInstalled(model) ? .installed : .notInstalled
        } catch {
            states[model] = .failed(error.localizedDescription)
        }
    }

    private func finish() {
        active = nil
        runTask = nil
        startNextIfIdle()
    }
}
