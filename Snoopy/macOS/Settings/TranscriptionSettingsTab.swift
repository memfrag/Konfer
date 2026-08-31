//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Which model transcribes, and what that costs.
///
/// There is nothing to choose here: the language of a recording decides its
/// model. It is still worth showing rather than hiding, because the two differ
/// by a factor of nine in speed and by 2.9 GB on disk, and a user who knows
/// that can read the progress bar rather than wonder about it.
struct TranscriptionSettingsTab: View {

    @Environment(AppSettings.self) private var appSettings
    @Environment(TranscriptionPipeline.self) private var pipeline

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            Section {
                ForEach(MeetingLanguage.allCases, id: \.self) { language in
                    LabeledContent(language.displayName) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ASRBackendKind(transcribing: language).displayName)
                            Text("about \(minutes(for: language)) per hour of audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text(
                    "The language you pick for a recording decides which model "
                    + "transcribes it. Apple's recognition covers 30 locales, "
                    + "and Swedish isn't one of them. KB-Whisper is the National "
                    + "Library of Sweden's Whisper model, trained on more than "
                    + "50,000 hours of Swedish."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Faster, less complete", isOn: $appSettings.fastTranscription)
                    .onChange(of: appSettings.fastTranscription) { _, value in
                        pipeline.fastTranscription = value
                    }
            } header: {
                Text("Speed")
            } footer: {
                Text(
                    "Transcribes the recording in parallel chunks, roughly twice "
                    + "as fast. It also drops speech, and does so unpredictably: "
                    + "the same recording produced 791, 657 and 639 words on "
                    + "three consecutive runs, against 813 twice with this off. "
                    + "Transcripts made this way are marked."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            pipeline.fastTranscription = appSettings.fastTranscription
        }
    }

    private func minutes(for language: MeetingLanguage) -> String {
        let value = ASRBackendKind(transcribing: language)
            .estimatedMinutesPerHourOfAudio
        return value < 2 ? "a minute" : "\(Int(value)) minutes"
    }
}

#Preview {
    TranscriptionSettingsTab()
        .previewEnvironment()
}
