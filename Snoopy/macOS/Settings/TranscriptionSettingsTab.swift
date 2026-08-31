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
                ForEach(Self.routing, id: \.model) { row in
                    LabeledContent(row.model.displayName) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.languages.map(\.displayName).joined(separator: ", "))
                                .multilineTextAlignment(.trailing)
                            Text("about \(minutes(for: row.model)) per hour of audio")
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
                    + "and Swedish, Danish, Dutch and Polish aren't among them. "
                    + "KB-Whisper is the National Library of Sweden's Whisper "
                    + "model, trained on more than 50,000 hours of Swedish; the "
                    + "other three go to OpenAI's multilingual Whisper."
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

    /// Which languages each model is responsible for, in picker order.
    ///
    /// Grouped by model rather than listed per language: ten rows saying the
    /// same three things is a wall, and the grouping *is* the information —
    /// what a model costs is a fact about the model, not about each language.
    private static var routing: [(model: ASRBackendKind, languages: [MeetingLanguage])] {
        var order: [ASRBackendKind] = []
        var grouped: [ASRBackendKind: [MeetingLanguage]] = [:]

        for language in MeetingLanguage.allCases {
            let model = ASRBackendKind(transcribing: language)
            if grouped[model] == nil { order.append(model) }
            grouped[model, default: []].append(language)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private func minutes(for model: ASRBackendKind) -> String {
        let value = model.estimatedMinutesPerHourOfAudio
        return value < 2 ? "a minute" : "\(Int(value)) minutes"
    }
}

#Preview {
    TranscriptionSettingsTab()
        .previewEnvironment()
}
