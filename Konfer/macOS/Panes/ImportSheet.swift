//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Asks for the two hints that actually help before a run starts.
///
/// The speaker count measurably improves clustering when the user knows it.
/// The language is load-bearing: it routes English to Apple's transcriber and
/// everything else to KB-Whisper, and it stops Whisper detecting a language
/// per chunk — which on a Swedish meeting full of English loanwords makes it
/// flip mid-recording.
///
/// It is also the only choice worth making: the model follows from it. An hour
/// of audio sent to the wrong one comes back as an hour of wrong words, so the
/// picker sits at the top of the sheet rather than in Settings.
struct ImportSheet: View {

    let url: URL

    /// Set when this exact file has been transcribed before.
    let alreadyTranscribed: Meeting?

    let onTranscribe: (MeetingLanguage, Int?) -> Void
    let onOpenExisting: (Meeting) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(ModelDownloadQueue.self) private var downloads

    @State private var language: MeetingLanguage = .english
    @State private var knowsSpeakerCount = false
    @State private var speakerCount = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Transcribe Recording")
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let alreadyTranscribed {
                duplicateNotice(alreadyTranscribed)
            }

            Form {
                Picker("Language:", selection: $language) {
                    ForEach(MeetingLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .help(
                    "The language decides which model transcribes: Apple's "
                    + "built-in recognition where it has the language, "
                    + "KB-Whisper for Swedish, and OpenAI's Whisper for Danish, "
                    + "Dutch and Polish."
                )

                if let missing = missingModel {
                    modelNotice(missing)
                }

                Toggle("I know how many people spoke", isOn: $knowsSpeakerCount)

                if knowsSpeakerCount {
                    Stepper(
                        "Speakers: \(speakerCount)",
                        value: $speakerCount,
                        in: 1...20
                    )
                    Text("Telling Konfer the number of speakers usually improves the result.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Transcribe") {
                    onTranscribe(language, knowsSpeakerCount ? speakerCount : nil)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(missingModel != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    /// The model this language needs and doesn't have yet.
    ///
    /// Nil for the languages Apple covers, whatever is on disk: macOS installs
    /// those itself on first use, so there is nothing to wait for.
    private var missingModel: ManagedModel? {
        guard let model = ManagedModel(transcribing: language) else { return nil }
        return downloads.state(of: model) == .installed ? nil : model
    }

    /// Says which model is missing and how big it is, rather than letting the
    /// user commit to a transcription that would stop to fetch three gigabytes.
    private func modelNotice(_ model: ManagedModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(language.displayName) needs \(model.displayName), "
                 + "\(ModelStorage.formattedSize(model.estimatedBytes)), "
                 + "which hasn't been downloaded yet.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Button(downloads.state(of: model).isBusy ? "Downloading…" : "Download\u{2026}") {
                downloads.enqueue(model)
                openWindow(id: ModelDownloadsWindow.windowID)
            }
            .controlSize(.small)
            .disabled(downloads.state(of: model).isBusy)
        }
        .padding(.vertical, 2)
    }

    private func duplicateNotice(_ meeting: Meeting) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 6) {
                Text("You've transcribed this recording before.")
                    .font(.callout)
                Button("Open the existing transcript") {
                    onOpenExisting(meeting)
                    dismiss()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    ImportSheet(
        url: URL(fileURLWithPath: "/tmp/Standup.m4a"),
        alreadyTranscribed: nil,
        onTranscribe: { _, _ in },
        onOpenExisting: { _ in }
    )
    .previewEnvironment()
}
#endif
