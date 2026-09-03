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
struct TranscriptImportSheet: View {

    let url: URL
    let transcript: KlangTranscript

    let onImport: (MeetingLanguage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var language: MeetingLanguage = .english

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
                LabeledContent("Speakers:", value: "\(transcript.speakerIDs.count)")
                LabeledContent("Length:", value: Timecode.short(transcript.duration))

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
            .formStyle(.grouped)

            noAudioNotice

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    onImport(language)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
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
        transcript: KlangTranscript(segments: [
            .init(text: "Att vi, det är helt rätt.", start: 0.18, end: 3.18, speaker: "Talare 1"),
            .init(text: "Ja, precis.", start: 3.76, end: 5.2, speaker: "Talare 2")
        ]),
        onImport: { _ in }
    )
    .previewEnvironment()
}
#endif
