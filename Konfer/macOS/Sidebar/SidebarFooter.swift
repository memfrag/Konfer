//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI

/// Shows what the pipeline is doing, or the last thing that went wrong.
///
/// The first run downloads several hundred megabytes of models, which is far
/// too long a wait to leave unexplained — so the stage, the fraction and the
/// queue depth are always visible rather than hidden behind a spinner.
struct SidebarFooter: View {

    @Environment(TranscriptionPipeline.self) private var pipeline
    @Environment(VideoExportQueue.self) private var videoExports
    @Environment(TranslationQueue.self) private var translations

    var body: some View {
        Group {
            // The pipeline first: it is the longer wait and the one the app
            // exists for. A video export is happy to wait its turn to be shown.
            if let error = pipeline.lastError {
                errorFooter(error)
                    .footerChrome()
            } else if let job = pipeline.activeJob {
                progressFooter(job)
                    .footerChrome()
            } else if translations.state.isTranslating {
                translationFooter()
                    .footerChrome()
            } else if videoExports.state.isExporting {
                exportFooter()
                    .footerChrome()
            } else if translations.state != .idle {
                translationFooter()
                    .footerChrome()
            } else if videoExports.state != .idle {
                exportFooter()
                    .footerChrome()
            }
        }
    }

    // MARK: - Progress

    private func progressFooter(_ job: TranscriptionPipeline.Job) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Button {
                    pipeline.cancelActive()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop transcribing")
            }

            if let fraction = pipeline.stage.fraction {
                ProgressView(value: fraction)
                    .controlSize(.small)
            } else {
                ProgressView()
                    .controlSize(.small)
            }

            HStack(spacing: 4) {
                Text(pipeline.stage.label)
                if let fraction = pipeline.stage.fraction, fraction > 0 {
                    Text("\(Int(fraction * 100))%")
                }
                if !pipeline.queue.isEmpty {
                    Text("· \(pipeline.queue.count) waiting")
                }

                Spacer()

                if let startedAt = pipeline.activeJobStartedAt {
                    // `Text(timerInterval:)` keeps its own time, so the clock
                    // ticks without the footer redrawing once a second.
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .help("Time spent on this recording")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Video export

    /// Copying an hour of screen recording takes minutes, so it reports the
    /// same way transcribing does rather than happening invisibly.
    @ViewBuilder private func exportFooter() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch videoExports.state {
            case .exporting(let fraction):
                HStack {
                    Text(videoExports.title ?? "Exporting video")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        videoExports.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop exporting")
                }

                ProgressView(value: fraction)
                    .controlSize(.small)

                HStack(spacing: 4) {
                    Text("Writing subtitled video")
                    if fraction > 0 { Text("\(Int(fraction * 100))%") }
                    Spacer()
                    if let startedAt = videoExports.startedAt {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

            case .finished(let url):
                Label {
                    Text("Exported \(url.lastPathComponent)")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                HStack {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                    Button("Dismiss") { videoExports.acknowledge() }
                        .controlSize(.small)
                }

            case .failed(let message):
                Label {
                    Text(message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Dismiss") { videoExports.acknowledge() }
                    .controlSize(.small)

            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Two minutes for an hour of meeting is long enough to need saying, and
    /// the count is exact — turns are the one unit of work in this app that can
    /// be counted rather than estimated.
    @ViewBuilder private func translationFooter() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch translations.state {
            case .translating(let done, let total):
                HStack {
                    Text(translations.title ?? "Translating")
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        translations.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop translating and keep the lines already done")
                }

                ProgressView(value: translations.state.fraction ?? 0)
                    .controlSize(.small)

                HStack(spacing: 4) {
                    Text("Translating")
                    Text("\(done) of \(total)")
                    Spacer()
                    if let startedAt = translations.startedAt {
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

            case .finished(let lines, let target):
                Label {
                    Text("Translated \(lines) \(lines == 1 ? "line" : "lines") into \(target.displayName)")
                        .font(.caption)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button("Dismiss") { translations.acknowledge() }
                    .controlSize(.small)

            case .failed(let message):
                Label {
                    Text(message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button("Dismiss") { translations.acknowledge() }
                    .controlSize(.small)

            case .idle:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Error

    private func errorFooter(_ error: PipelineError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.caption)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Dismiss") {
                pipeline.clearError()
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// Padding lives on the content, so an idle footer takes up no space at all.
    func footerChrome() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview {
    SidebarFooter()
        .previewEnvironment()
}
#endif
