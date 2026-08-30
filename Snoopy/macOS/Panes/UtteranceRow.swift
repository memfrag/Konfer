//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI

/// One speaker turn in the transcript.
struct UtteranceRow: View {

    let utterance: Utterance
    let speakerName: String
    let color: Color
    let isActive: Bool
    let activeWordIndex: Int?
    let otherSpeakers: [SpeakerLabel]

    /// False at the ends of the transcript, where there is no neighbour.
    let canMergePrevious: Bool
    let canMergeNext: Bool

    let onSeek: () -> Void
    /// Seek to an exact moment within this turn, when a word is clicked.
    let onSeekTo: (TimeInterval) -> Void
    let onEdit: (String) -> Void
    let onReassign: (String) -> Void
    let onSplit: () -> Void
    let onMerge: (MergeDirection) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            Button(action: onSeek) {
                Text(Timecode.short(utterance.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 56, alignment: .trailing)
            .help("Jump to this point")

            Rectangle()
                .fill(color)
                .frame(width: 3)
                .opacity(isActive ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(speakerName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                    if utterance.isEdited {
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Edited by hand — word timings no longer apply to this line.")
                    }
                }

                if isEditing {
                    editor
                } else {
                    text
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu { menu }
    }

    // MARK: - Text

    @ViewBuilder private var text: some View {
        if let words = utterance.words {
            // Clicking a word seeks to it. Text is not selectable here — see
            // `TranscriptText`; selection lives in edit mode.
            TranscriptText(
                tokens: WordToken.tokens(from: words),
                activeWordIndex: isActive ? activeWordIndex : nil,
                onSeek: onSeekTo
            )
        } else {
            // An edited turn has no word timings left, so the whole line seeks
            // to its own start.
            Text(utterance.text)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSeek)
                .accessibilityAddTraits(.isButton)
        }
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // The one place transcript text is selectable and editable.
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator)
                )
            HStack {
                Button("Cancel") { isEditing = false }
                Button("Save") {
                    isEditing = false
                    onEdit(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Menu

    @ViewBuilder private var menu: some View {
        // First, because reading is the common case and text is not selectable
        // while reading — see `TranscriptText`.
        Button("Copy Text") {
            copy(utterance.text)
        }

        Button("Copy with Speaker and Time") {
            copy(TranscriptExporter.plainLine(for: utterance, speaker: speakerName))
        }

        Divider()

        Button("Edit Text…") {
            draft = utterance.text
            isEditing = true
        }

        if !otherSpeakers.isEmpty {
            Menu("Reassign to") {
                ForEach(otherSpeakers) { speaker in
                    Button(speaker.name) { onReassign(speaker.id) }
                }
            }
        }

        Divider()

        Button("Split at Playhead", action: onSplit)
            .disabled(utterance.words == nil || !isActive)

        Button("Merge with Previous") { onMerge(.previous) }
            .disabled(!canMergePrevious)

        Button("Merge with Next") { onMerge(.next) }
            .disabled(!canMergeNext)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
