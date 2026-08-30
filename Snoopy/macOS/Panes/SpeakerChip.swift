//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A speaker's name, renameable in place.
///
/// When the enrollment roster thinks it recognises this voice, the chip offers
/// the name as a suggestion. Suggestions are never applied on their own: a
/// wrong guess would stamp a real person's name across an hour of transcript,
/// and "Speaker 2" is a much better failure than the wrong name.
struct SpeakerChip: View {

    let speaker: SpeakerLabel
    let color: Color

    let onRename: (String) -> Void
    let onAcceptSuggestion: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                    .onExitCommand { isEditing = false }
            } else {
                nameLabel
            }

            if let suggestion = speaker.suggestion, !speaker.isNamed, !isEditing {
                suggestionButton(suggestion)
            }
        }
    }

    private var nameLabel: some View {
        Button {
            draft = speaker.name
            isEditing = true
            isFieldFocused = true
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(speaker.name)
                    .font(.callout)
                    .fontWeight(speaker.isNamed ? .semibold : .regular)
                    .foregroundStyle(speaker.isNamed ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Click to rename")
    }

    private func suggestionButton(_ suggestion: EnrollmentSuggestion) -> some View {
        Button(action: onAcceptSuggestion) {
            Text("Sounds like \(suggestion.name)?")
                .font(.caption)
        }
        .buttonStyle(.link)
        .help(
            String(
                format: "Voice match, distance %.2f. Nothing is renamed until you accept.",
                suggestion.distance
            )
        )
    }

    private func commit() {
        isEditing = false
        onRename(draft)
    }
}
