//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// Runs one subtitled video export at a time, and says how it is going.
///
/// Modelled on ``ModelDownloadQueue``, and here for the same reason: copying an
/// hour of screen recording takes long enough that it needs a progress bar, and
/// the work has to outlive the pane that started it. Someone who kicks off an
/// export and then goes to read another transcript should not silently cancel
/// their own export by navigating away.
///
/// One at a time. Two exports would fight over the disk and finish later than
/// if they had queued, and nobody asks for two at once.
///
@Observable @MainActor
final class VideoExportQueue {

    enum State: Equatable {
        case idle
        case exporting(Double)
        case finished(URL)
        case failed(String)

        var isExporting: Bool {
            if case .exporting = self { return true }
            return false
        }

        var fraction: Double? {
            if case .exporting(let value) = self { return value }
            return nil
        }
    }

    private(set) var state: State = .idle

    /// The meeting being exported, for the footer to name.
    private(set) var title: String?

    /// When it started, for the elapsed clock.
    private(set) var startedAt: Date?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Injected so tests need not copy a gigabyte of video.
    @ObservationIgnored private let write: @Sendable (
        Meeting, URL, Bool, TranscriptRendering, @Sendable @escaping (Double) -> Void
    ) async throws -> Void

    init(
        write: @escaping @Sendable (
            Meeting, URL, Bool, TranscriptRendering, @Sendable @escaping (Double) -> Void
        ) async throws -> Void = { meeting, url, trimmed, rendering, progress in
            try await SubtitledVideoWriter.write(
                meeting: meeting, to: url, trimmed: trimmed,
                rendering: rendering, progress: progress
            )
        }
    ) {
        self.write = write
    }

    // MARK: - Running

    func export(
        _ meeting: Meeting,
        to destination: URL,
        trimmed: Bool,
        rendering: TranscriptRendering = .original
    ) {
        guard !state.isExporting else { return }

        title = meeting.title
        startedAt = Date()
        state = .exporting(0)

        // Captured once, weakly, rather than inside the run below: a late
        // callback from a cancelled export must not resurrect the bar — the
        // same guard the download queue keeps.
        let onProgress: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self, self.state.isExporting else { return }
                self.state = .exporting(min(max(fraction, 0), 1))
            }
        }

        task = Task { [weak self, write] in
            do {
                try await write(meeting, destination, trimmed, rendering, onProgress)
                await MainActor.run {
                    guard let self, self.state.isExporting else { return }
                    self.state = .finished(destination)
                    self.startedAt = nil
                }
            } catch is CancellationError {
                // Cancelling leaves nothing behind, including a half-written
                // movie at the destination the user picked.
                try? FileManager.default.removeItem(at: destination)
                await MainActor.run {
                    self?.state = .idle
                    self?.startedAt = nil
                }
            } catch {
                try? FileManager.default.removeItem(at: destination)
                await MainActor.run {
                    self?.state = .failed(Self.describe(error))
                    self?.startedAt = nil
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func acknowledge() {
        guard !state.isExporting else { return }
        state = .idle
        title = nil
        startedAt = nil
    }

    private static func describe(_ error: Error) -> String {
        guard let export = error as? VideoExportError else {
            return error.localizedDescription
        }
        return [export.errorDescription, export.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
