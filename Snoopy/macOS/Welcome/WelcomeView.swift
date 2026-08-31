//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The first thing a new user sees, and the only place Snoopy asks for anything
/// up front.
///
/// It exists because of one number: the models are gigabytes, and until now
/// they arrived silently in the middle of the first transcription. Asking which
/// languages matter turns that into a decision — and for someone who only needs
/// the languages Apple covers, the honest answer is that there is nothing to
/// download at all, which this screen can say plainly.
struct WelcomeView: View {

    /// Called when the user is finished, whether they downloaded or skipped.
    let onFinish: (_ openDownloads: Bool) -> Void

    @Environment(AppSettings.self) private var appSettings
    @Environment(ModelDownloadQueue.self) private var downloads

    /// Starts on the default import language, so the common case is one click.
    @State private var selected: Set<MeetingLanguage> = [.english]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Snoopy")
                    .font(.title2.weight(.semibold))
                Text(
                    "Snoopy transcribes meetings on this Mac. Recordings and "
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

            Text(requirement)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("You can change this later in Settings ▸ Models.")
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

    // MARK: - What the choice costs

    /// Models the selected languages need that aren't on disk yet.
    ///
    /// Diarization is included because every transcription uses it, whatever
    /// the language — it is the one download nobody can opt out of.
    private var needed: [ManagedModel] {
        var models: [ManagedModel] = []
        if !ManagedModel.diarization.isInstalled { models.append(.diarization) }
        for language in MeetingLanguage.allCases where selected.contains(language) {
            if let model = ManagedModel(transcribing: language),
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

        guard downloading, !needed.isEmpty else {
            onFinish(false)
            return
        }
        downloads.enqueueEverythingNeeded(for: Array(selected))
        onFinish(true)
    }
}

#Preview {
    WelcomeView { _ in }
        .previewEnvironment()
}
