//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// What the speech models cost on disk, and how to get that space back.
///
/// The models are hundreds of megabytes downloaded silently on first use, which
/// is too much to leave invisible. Deleting them is safe: the next transcription
/// downloads them again.
struct ModelsSettingsTab: View {

    @Environment(TranscriptionPipeline.self) private var pipeline

    @State private var fluidAudioSize: Int64 = 0
    @State private var whisperSize: Int64 = 0
    @State private var isDeleting = false
    @State private var deletionError: String?

    private var totalSize: Int64 { fluidAudioSize + whisperSize }

    var body: some View {
        Form {
            Section {
                LabeledContent("Speech recognition") {
                    Text(whisperSize > 0
                         ? ModelStorage.formattedSize(whisperSize)
                         : "Not downloaded")
                }
                LabeledContent("Speaker identification") {
                    Text(fluidAudioSize > 0
                         ? ModelStorage.formattedSize(fluidAudioSize)
                         : "Not downloaded")
                }
                LabeledContent("Total") {
                    Text(totalSize > 0 ? ModelStorage.formattedSize(totalSize) : "Nothing downloaded")
                        .fontWeight(.medium)
                }
            } header: {
                Text("Speech Models")
            } footer: {
                Text(
                    "Snoopy downloads its speech and speaker models once, then works "
                    + "entirely offline. Deleting them frees the space; the next "
                    + "transcription downloads them again. Apple's own English "
                    + "recognition isn't listed here — macOS manages it."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(
                            nil,
                            inFileViewerRootedAtPath: ModelStorage.directory.path
                        )
                    }
                    .disabled(totalSize == 0)

                    Spacer()

                    Button("Delete Models", role: .destructive) {
                        Task { await deleteModels() }
                    }
                    .disabled(totalSize == 0 || isDeleting || pipeline.isRunning)
                }

                if pipeline.isRunning {
                    Text("Can't delete models while a transcription is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let deletionError {
                    Text(deletionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task { refreshSize() }
    }

    private var displayPath: String {
        ModelStorage.directory.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func refreshSize() {
        fluidAudioSize = ModelStorage.sizeOnDisk()
        whisperSize = KBWhisperModelStore.sizeOnDisk()
    }

    private func deleteModels() async {
        isDeleting = true
        deletionError = nil
        defer { isDeleting = false }

        // Drop the in-memory models first, so nothing keeps reading files that
        // are about to disappear.
        await pipeline.unloadModels()

        do {
            try ModelStorage.removeAll()
            try KBWhisperModelStore.removeAll()
        } catch {
            deletionError = error.localizedDescription
        }
        refreshSize()
    }
}

#Preview {
    ModelsSettingsTab()
        .previewEnvironment()
}
