//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Switches the transcript between the language it was spoken in and the one
/// it was translated into.
///
/// A bar of its own rather than a control in the playback bar, whose two items
/// are the things you can do to the *recording*. This is a property of the
/// transcript, and has to work for a meeting that never had a recording at all
/// — an imported transcript has no playback bar to hang it from.
struct TranscriptLanguageBar: View {

    let meeting: Meeting

    @Binding var rendering: TranscriptRendering

    let onTranslate: () -> Void
    let onFillGaps: () -> Void
    let onRemove: () -> Void

    @Environment(TranslationQueue.self) private var translations

    var body: some View {
        HStack(spacing: 10) {
            if let target = meeting.translationTarget {
                Picker("", selection: $rendering) {
                    Text(meeting.language.displayName).tag(TranscriptRendering.original)
                    Text(target.displayName).tag(TranscriptRendering.translated)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                Text(meeting.language.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isTranslatingThis {
                ProgressView()
                    .controlSize(.small)
                Text("Translating\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if meeting.translationTarget == nil {
                Button("Translate\u{2026}", action: onTranslate)
                    .controlSize(.small)
            } else {
                if untranslated > 0 {
                    Text("\(untranslated) not translated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Translate the Rest", action: onFillGaps)
                        .controlSize(.small)
                }
                Menu {
                    Button("Translate Into\u{2026}", action: onTranslate)
                    Divider()
                    Button("Remove Translation", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Translate into another language, or forget this one")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var isTranslatingThis: Bool {
        translations.state.isTranslating && translations.meetingID == meeting.id
    }

    /// Kept turns with nothing to show in the translation language — what an
    /// edit since the last run looks like from here.
    private var untranslated: Int {
        meeting.untranslatedKeptUtterances.count
    }
}
