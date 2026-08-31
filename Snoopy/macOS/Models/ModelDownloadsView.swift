//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// What Snoopy needs to transcribe, what it already has, and what is on its way.
///
/// The models are the one part of an offline transcriber that isn't offline, so
/// this window says the size before anything starts rather than after.
struct ModelDownloadsView: View {

    @Environment(ModelDownloadQueue.self) private var downloads
    @Environment(TranscriptionPipeline.self) private var pipeline

    @State private var deletionError: String?

    /// Sizes on disk, measured once rather than per render: reading them walks
    /// a model's whole directory, which for KB-Whisper is thousands of files.
    @State private var sizes: [ManagedModel: Int64] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    ForEach(ManagedModel.allCases) { model in
                        row(for: model)
                    }
                } header: {
                    Text("Speech Models")
                } footer: {
                    footer
                }
            }
            .formStyle(.grouped)

            Divider()
            actions
        }
        .frame(width: 460)
        .onAppear {
            downloads.refresh()
            measure()
        }
        // A finished download changes what is on disk, so re-measure then —
        // and only then.
        .onChange(of: downloads.isRunning) { _, _ in measure() }
    }

    // MARK: - Rows

    private func row(for model: ManagedModel) -> some View {
        LabeledContent {
            state(of: model)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                Text(subtitle(for: model))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The languages a model unlocks, which is the only reason to want it.
    private func subtitle(for model: ManagedModel) -> String {
        let languages = model.languages
        guard !languages.isEmpty else { return model.summary }
        return languages.map(\.displayName).joined(separator: ", ")
    }

    @ViewBuilder
    private func state(of model: ManagedModel) -> some View {
        switch downloads.state(of: model) {

        case .installed:
            HStack(spacing: 6) {
                Text(ModelStorage.formattedSize(sizes[model] ?? model.estimatedBytes))
                    .foregroundStyle(.secondary)
                Button("Delete", role: .destructive) { delete(model) }
                    .controlSize(.small)
                    .disabled(pipeline.isRunning)
            }

        case .notInstalled:
            HStack(spacing: 6) {
                Text(ModelStorage.formattedSize(model.estimatedBytes))
                    .foregroundStyle(.secondary)
                Button("Download") { downloads.enqueue(model) }
                    .controlSize(.small)
            }

        case .queued:
            Text("Waiting…")
                .foregroundStyle(.secondary)

        case .downloading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Text(fraction > 0 ? "\(Int(fraction * 100))%" : "Starting…")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            HStack(spacing: 6) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button("Retry") { downloads.enqueue(model) }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Chrome

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Downloaded once, then Snoopy works offline. Apple's own "
                + "languages aren't listed — macOS installs those itself the "
                + "first time you use one."
            )
            if let deletionError {
                Text(deletionError)
                    .foregroundStyle(.red)
            }
            if pipeline.isRunning {
                Text("Models can't be deleted while a transcription is running.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack {
            if downloads.isRunning {
                Text("\(ModelStorage.formattedSize(downloads.remainingBytes)) left to download")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if downloads.isRunning {
                Button("Stop") { downloads.cancelAll() }
            } else {
                Button("Download All") {
                    for model in ManagedModel.allCases { downloads.enqueue(model) }
                }
                .disabled(ManagedModel.allCases.allSatisfy { $0.isInstalled })
            }
        }
        .padding(12)
    }

    // MARK: - Actions

    /// Reads what each installed model actually costs, off the main thread.
    private func measure() {
        Task {
            let measured = await Task.detached {
                var sizes: [ManagedModel: Int64] = [:]
                for model in ManagedModel.allCases where model.isInstalled {
                    sizes[model] = model.sizeOnDisk()
                }
                return sizes
            }.value
            sizes = measured
        }
    }

    private func delete(_ model: ManagedModel) {
        deletionError = nil
        // Loaded models keep file handles on what is about to disappear.
        Task {
            await pipeline.unloadModels()
            do {
                try downloads.remove(model)
                measure()
            } catch {
                deletionError = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview {
    ModelDownloadsView()
        .previewEnvironment()
}
#endif
