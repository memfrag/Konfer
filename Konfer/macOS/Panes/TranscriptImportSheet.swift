//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Confirms an already-finished transcript into the library.
///
/// Deliberately not ``ImportSheet``: the two sheets ask for the same field and
/// mean different things by it. There, the language picks the model and a
/// wrong answer costs an hour of wrong words; here nothing will be
/// transcribed, so it is only what the transcript gets filed as. Everything
/// else on that sheet — the speaker count, the model download — has nothing to
/// answer to, and the summary below takes their place: what the file turned
/// out to contain, before it becomes a meeting.
///
/// A Konfer export already says what language it is in, so for one of those
/// the language is shown rather than asked: the only way to answer the
/// question differently is to answer it wrongly.
struct TranscriptImportSheet: View {

    let url: URL
    let transcript: ImportedTranscript

    /// The folder the file was dropped on, which wins over the usual one.
    var initialFolder: MeetingFolder?

    let onImport: (MeetingLanguage, MeetingFolder) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(LibrarySelection.self) private var librarySelection

    @State private var language: MeetingLanguage = .english
    @State private var folder: MeetingFolder = .root

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Import Transcript")
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Form {
                if case .konfer(let export) = transcript {
                    LabeledContent("Title:", value: export.title)
                }
                LabeledContent("Speakers:", value: "\(transcript.speakerCount)")
                LabeledContent("Length:", value: Timecode.short(transcript.duration))

                if let declared = transcript.declaredLanguage {
                    LabeledContent("Language:", value: declared.displayName)
                } else {
                    Picker("Language:", selection: $language) {
                        ForEach(MeetingLanguage.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .help(
                        "Nothing is transcribed on import — the language is only "
                        + "recorded with the transcript."
                    )
                }

                if case .konfer(let export) = transcript, let target = export.translationTarget {
                    LabeledContent("Translation:", value: target.displayName)
                }

                FolderPicker(folder: $folder)
            }
            .formStyle(.grouped)

            noAudioNotice

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    onImport(language, folder)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            language = transcript.declaredLanguage ?? language
            folder = initialFolder
                ?? librarySelection.folderForNewMeeting(settings: appSettings, in: meetingStore)
        }
    }

    /// Said here rather than discovered later, because the missing player is
    /// the one way an imported meeting looks broken instead of finished.
    private var noAudioNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "waveform.slash")
                .foregroundStyle(.secondary)
            Text("A transcript file carries no recording, so this one imports "
                 + "without playback. You can point it at the recording "
                 + "afterwards.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    TranscriptImportSheet(
        url: URL(fileURLWithPath: "/tmp/klang-transcript.json"),
        transcript: .klang(KlangTranscript(segments: [
            .init(text: "Att vi, det är helt rätt.", start: 0.18, end: 3.18, speaker: "Talare 1"),
            .init(text: "Ja, precis.", start: 3.76, end: 5.2, speaker: "Talare 2")
        ])),
        onImport: { _, _ in }
    )
    .previewEnvironment()
}
#endif
