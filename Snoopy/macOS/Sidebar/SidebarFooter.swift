//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Shows what the pipeline is doing, or the last thing that went wrong.
///
/// The first run downloads several hundred megabytes of models, which is far
/// too long a wait to leave unexplained — so the stage, the fraction and the
/// queue depth are always visible rather than hidden behind a spinner.
struct SidebarFooter: View {

    @Environment(TranscriptionPipeline.self) private var pipeline

    var body: some View {
        Group {
            if let error = pipeline.lastError {
                errorFooter(error)
                    .footerChrome()
            } else if let job = pipeline.activeJob {
                progressFooter(job)
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
