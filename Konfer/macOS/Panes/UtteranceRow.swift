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

    /// Search matches inside this turn, and which of them the find bar is on.
    let searchMatches: [TranscriptMatch]
    let currentSearchMatch: TranscriptMatch?

    /// Whether clicking a word should offer what can be done at it.
    let offersWordActions: Bool
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
    /// Splits this turn before the word at the given index.
    let onSplitBefore: (Int) -> Void
    let onMerge: (MergeDirection) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    /// Whether the pointer is over this turn, which is when the merge buttons
    /// in the margin become available.
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            margin

            Rectangle()
                .fill(color)
                .frame(width: 3)
                .opacity(isActive ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    speakerControl
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
        .onHover { hover in
            withAnimation {
                isHovering = hover
            }
        }
        .contextMenu { menu }
    }

    // MARK: - Margin

    /// The time, and what can be done to this turn's edges.
    ///
    /// The merge buttons live here because this is where the boundary between
    /// two turns actually is — the diarizer breaking one turn into two is a
    /// mistake you see in the left margin, as a second timestamp where none
    /// should be.
    private var margin: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Button(action: onSeek) {
                Text(Timecode.short(utterance.start))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Jump to this point")

            Spacer()

            HStack(spacing: 2) {
                mergeButton(
                    .previous,
                    systemImage: "arrow.up.to.line.circle.fill",
                    isEnabled: canMergePrevious,
                    help: "Merge with the turn above"
                )
                mergeButton(
                    .next,
                    systemImage: "arrow.down.to.line.circle.fill",
                    isEnabled: canMergeNext,
                    help: "Merge with the turn below"
                )
            }
            // Always laid out, only ever shown on hover: appearing on hover is
            // helpful, but a transcript whose lines jump as the pointer crosses
            // them is not.
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .frame(width: 56, alignment: .trailing)
    }

    private func mergeButton(
        _ direction: MergeDirection,
        systemImage: String,
        isEnabled: Bool,
        help: String
    ) -> some View {
        Button {
            onMerge(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!isEnabled)
        .help(help)
    }

    // MARK: - Speaker

    /// The speaker's name, and — when there is anyone to swap it for — a menu
    /// for putting this line on someone else.
    ///
    /// The diarizer misattributes a line here and there, so the fix belongs on
    /// the thing that is wrong rather than behind a right-click on the row.
    @ViewBuilder private var speakerControl: some View {
        if otherSpeakers.isEmpty {
            nameLabel
        } else {
            Menu {
                reassignMenu
            } label: {
                nameLabel
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Reassign this line to another speaker")
        }
    }

    /// Offered from both the name and the row's context menu, so it is written
    /// once.
    @ViewBuilder private var reassignMenu: some View {
        Menu("Reassign to") {
            ForEach(otherSpeakers) { speaker in
                Button(speaker.name) { onReassign(speaker.id) }
            }
        }
    }

    private var nameLabel: some View {
        Text(speakerName)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
    }

    // MARK: - Text

    @ViewBuilder private var text: some View {
        if let words = utterance.words {
            // Clicking a word seeks to it. Text is not selectable here — see
            // `TranscriptText`; selection lives in edit mode.
            TranscriptText(
                tokens: WordToken.tokens(from: words),
                activeWordIndex: isActive ? activeWordIndex : nil,
                searchMatches: searchMatches,
                currentSearchMatch: currentSearchMatch,
                offersActions: offersWordActions,
                onSeek: onSeekTo,
                onSplitBefore: onSplitBefore
            )
        } else {
            // An edited turn has no word timings left, so the whole line seeks
            // to its own start.
            // An edited turn has no tokens to tint, so the highlight goes on
            // the string itself.
            Text(highlighted(utterance.text))
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSeek)
                .accessibilityAddTraits(.isButton)
        }
    }

    /// The turn's text with its search matches marked.
    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for match in searchMatches {
            guard let range = Self.range(of: match, in: attributed) else { continue }
            let isCurrent = match == currentSearchMatch
            attributed[range].backgroundColor = isCurrent
                ? .orange.opacity(0.55)
                : .yellow.opacity(0.35)
        }
        return attributed
    }

    private static func range(
        of match: TranscriptMatch,
        in attributed: AttributedString
    ) -> Range<AttributedString.Index>? {
        let characters = attributed.characters
        guard match.offset >= 0,
              match.offset + match.length <= characters.count else { return nil }
        let start = characters.index(characters.startIndex, offsetBy: match.offset)
        let end = characters.index(start, offsetBy: match.length)
        return start..<end
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
            reassignMenu
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
