//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Asks which language to translate a finished transcript into.
///
/// Deliberately shaped like ``ImportSheet``: a picker, a notice when something
/// is missing, and a confirm button that refuses rather than starting a run
/// that would stop halfway. The two sheets are answering the same kind of
/// question, and should not look like they come from different apps.
struct TranslateSheet: View {

    let meeting: Meeting
    let onTranslate: (MeetingLanguage) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var target: MeetingLanguage
    @State private var availability: TranslationAvailability?
    @State private var downloading: TranslationPair?

    init(meeting: Meeting, onTranslate: @escaping (MeetingLanguage) -> Void) {
        self.meeting = meeting
        self.onTranslate = onTranslate
        let existing = meeting.translationTarget
        _target = State(
            initialValue: existing ?? TranslationSupport.targets(for: meeting.language).first ?? .english
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 4) {
                Text("Translate Transcript")
                    .font(.headline)
                Text(meeting.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Form {
                LabeledContent("From:", value: meeting.language.displayName)

                Picker("Into:", selection: $target) {
                    ForEach(TranslationSupport.targets(for: meeting.language), id: \.self) { language in
                        if TranslationSupport.isKnownUnavailable(from: meeting.language, to: language) {
                            Text("\(language.displayName) — not available").tag(language)
                        } else {
                            Text(language.displayName).tag(language)
                        }
                    }
                }

                switch availability {
                case .needsDownload:
                    downloadNotice
                case .unavailable:
                    unavailableNotice
                case .ready, .none:
                    expectation
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Translate") {
                    onTranslate(target)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(availability != .ready)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(
            TranslationDownloadPrompt(pair: downloading) {
                downloading = nil
                Task { await check() }
            }
        )
        .task(id: target) { await check() }
    }

    // MARK: - Notices

    /// What the wait is, before anyone commits to it. Measured rather than
    /// guessed, in the spirit of the rest of the app's estimates.
    private var expectation: some View {
        Text("About two minutes for an hour of meeting. Everything stays on "
             + "this Mac, and the original transcript is kept — the pane "
             + "switches between them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var downloadNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(meeting.language.displayName) to \(target.displayName) hasn't "
                 + "been downloaded yet. macOS keeps these, not Konfer, so there "
                 + "is nothing in Settings ▸ Models for them.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Button(downloading == nil ? "Download\u{2026}" : "Downloading\u{2026}") {
                downloading = TranslationPair(source: meeting.language, target: target)
            }
            .controlSize(.small)
            .disabled(downloading != nil)
        }
        .padding(.vertical, 2)
    }

    /// The four pairs macOS has no path for. Says why there is no button.
    private var unavailableNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("macOS can't translate \(meeting.language.displayName) into "
                 + "\(target.displayName). Konfer won't route it through English: "
                 + "you would get a fluent \(target.displayName) sentence that is a "
                 + "translation of a translation, with nothing on screen to say "
                 + "which half to distrust.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Availability

    /// One live check, for the language actually chosen.
    ///
    /// Not nine when the sheet opens: `LanguageAvailability` answers one pair
    /// per await, and the pairs macOS refuses outright are already known from
    /// ``TranslationSupport``.
    private func check() async {
        availability = nil
        guard !TranslationSupport.isKnownUnavailable(from: meeting.language, to: target) else {
            availability = .unavailable
            return
        }
        let result = await TranscriptTranslator.availability(from: meeting.language, to: target)
        guard !Task.isCancelled else { return }
        availability = result
    }
}
