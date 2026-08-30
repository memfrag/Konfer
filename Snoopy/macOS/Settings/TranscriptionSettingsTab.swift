//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Which model transcribes, and what that costs.
///
/// The trade-off here is large enough to be worth showing rather than hiding:
/// on real Swedish meeting audio the models differ from "unreadable" to
/// "essentially clean", and from one minute per hour of audio to nine.
struct TranscriptionSettingsTab: View {

    @Environment(AppSettings.self) private var appSettings
    @Environment(TranscriptionPipeline.self) private var pipeline

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            Section {
                Picker("Model:", selection: $appSettings.asrBackend) {
                    ForEach(ASRBackendKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .onChange(of: appSettings.asrBackend) { _, kind in
                    pipeline.selectedBackend = kind
                }

                Text(appSettings.asrBackend.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("An hour of audio takes") {
                    Text("about \(minutes) on this Mac")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Speech Recognition")
            } footer: {
                Text(
                    "KB-Whisper is the National Library of Sweden's Whisper model, "
                    + "trained on more than 50,000 hours of Swedish. Parakeet is "
                    + "much faster and fine for English, but garbles Swedish. "
                    + "A change applies to the next recording you transcribe; "
                    + "anything already queued keeps the model it started with."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { pipeline.selectedBackend = appSettings.asrBackend }
    }

    private var minutes: String {
        let value = appSettings.asrBackend.estimatedMinutesPerHourOfAudio
        return value < 2 ? "a minute" : "\(Int(value)) minutes"
    }
}

#Preview {
    TranscriptionSettingsTab()
        .previewEnvironment()
}
