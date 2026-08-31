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
                    "The language decides which model transcribes: English goes "
                    + "to Apple's built-in recognition, Swedish to KB-Whisper "
                    + "Large."
                )

                Toggle("I know how many people spoke", isOn: $knowsSpeakerCount)

                if knowsSpeakerCount {
                    Stepper(
                        "Speakers: \(speakerCount)",
                        value: $speakerCount,
                        in: 1...20
                    )
                    Text("Telling Snoopy the number of speakers usually improves the result.")
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
            }
        }
        .padding(20)
        .frame(width: 420)
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

#Preview {
    ImportSheet(
        url: URL(fileURLWithPath: "/tmp/Standup.m4a"),
        alreadyTranscribed: nil,
        onTranscribe: { _, _ in },
        onOpenExisting: { _ in }
    )
}
