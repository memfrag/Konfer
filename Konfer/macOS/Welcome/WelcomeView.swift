//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The first thing a new user sees, and the only place Konfer asks for anything
/// up front.
///
/// It exists because of one number: the models are gigabytes, and until now
/// they arrived silently in the middle of the first transcription. Asking which
/// languages matter turns that into a decision — and for someone who only needs
/// the languages Apple covers, the honest answer is that there is nothing to
/// download at all, which this screen can say plainly.
///
/// A language with more than one model gets a picker here too, because the
/// choice is mostly a download: Whisper large-v3 instead of Apple is 3 GB more,
/// and Pianissimo instead of KB-Whisper is 2.3 GB less. What is picked is
/// remembered as ``RememberedModels``, so the Transcribe sheet opens on it.
struct WelcomeView: View {

    /// Called when the user is finished, whether they downloaded or skipped.
    let onFinish: (_ openDownloads: Bool) -> Void

    @Environment(AppSettings.self) private var appSettings
    @Environment(ModelDownloadQueue.self) private var downloads

    /// Starts on the default import language, so the common case is one click.
    @State private var selected: Set<MeetingLanguage> = [.english]

    /// Shared with the Transcribe sheet, which opens on what is picked here.
    @AppStorage("rememberedTranscriptionModels") private var rememberedModels = ""

    /// Models picked on this screen, by language. A language not in here is
    /// on whatever is remembered for it, or its default.
    @State private var picked: [MeetingLanguage: ASRBackendKind] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Konfer")
                    .font(.title2.weight(.semibold))
                Text(
                    "Konfer transcribes meetings on this Mac. Recordings and "
                    + "transcripts never leave it — the only thing it fetches "
                    + "is the speech models themselves."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Which languages do you record in?")
                    .font(.headline)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(MeetingLanguage.allCases, id: \.self) { language in
                        Toggle(language.displayName, isOn: binding(for: language))
                            .toggleStyle(.checkbox)
                    }
                }
            }

            if !languagesWithChoices.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(languagesWithChoices, id: \.self) { language in
                        modelPicker(for: language)
                    }
                }
            }

            Text(requirement)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("You can download more later from Window ▸ Models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { finish(downloading: false) }
                Button(needed.isEmpty ? "Get Started" : "Download") {
                    finish(downloading: true)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Models

    /// Selected languages that have a model to choose, in menu order.
    private var languagesWithChoices: [MeetingLanguage] {
        MeetingLanguage.allCases.filter {
            selected.contains($0) && ASRBackendKind.choices(for: $0).count > 1
        }
    }

    /// What each language is set to: picked here, else remembered, else its
    /// default.
    private var chosenModels: RememberedModels {
        var models = RememberedModels(rememberedModels)
        for (language, model) in picked {
            models.remember(model, for: language)
        }
        return models
    }

    private func modelPicker(for language: MeetingLanguage) -> some View {
        let model = chosenModels.model(for: language)
        return VStack(alignment: .leading, spacing: 2) {
            Picker("\(language.displayName) model:", selection: Binding(
                get: { model },
                set: { picked[language] = $0 }
            )) {
                ForEach(ASRBackendKind.choices(for: language), id: \.self) { choice in
                    Text(ManagedModel(for: choice)?.displayName ?? choice.displayName)
                        .tag(choice)
                }
            }
            .fixedSize()
            Text(model.caption(in: language))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - What the choice costs

    /// Models the selected languages need that aren't on disk yet.
    ///
    /// Diarization is included because every transcription uses it, whatever
    /// the language — it is the one download nobody can opt out of.
    private var needed: [ManagedModel] {
        var models: [ManagedModel] = []
        if !ManagedModel.diarization.isInstalled { models.append(.diarization) }
        for language in MeetingLanguage.allCases where selected.contains(language) {
            if let model = ManagedModel(for: chosenModels.model(for: language)),
               !model.isInstalled,
               !models.contains(model) {
                models.append(model)
            }
        }
        return models
    }

    private var requirement: String {
        guard !needed.isEmpty else {
            return "Everything needed is already downloaded."
        }
        let total = needed.reduce(0) { $0 + $1.estimatedBytes }
        let names = needed.map(\.displayName).joined(separator: ", ")
        return "\(names) — about \(ModelStorage.formattedSize(total)) to download."
    }

    private func binding(for language: MeetingLanguage) -> Binding<Bool> {
        Binding(
            get: { selected.contains(language) },
            set: { isOn in
                if isOn { selected.insert(language) } else { selected.remove(language) }
            }
        )
    }

    // MARK: - Finishing

    private func finish(downloading: Bool) {
        appSettings.hasCompletedOnboarding = true
        // Remembered even when skipping: it is what the Transcribe sheet
        // should open on, whether or not the download happens now.
        rememberedModels = chosenModels.stored

        guard downloading, !needed.isEmpty else {
            onFinish(false)
            return
        }
        downloads.enqueueEverythingNeeded(for: Array(selected), models: chosenModels)
        onFinish(true)
    }
}

#if DEBUG
#Preview {
    WelcomeView { _ in }
        .previewEnvironment()
}
#endif
