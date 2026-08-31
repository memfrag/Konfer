//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Find and replace within the open transcript.
///
/// Sits above the transcript rather than floating over it, so it never covers
/// the line you are looking for — which on a thousand-line transcript is the
/// line you just found.
struct TranscriptFindBar: View {

    @Bindable var controller: TranscriptFindController

    /// Replaces the current match. Returns what it cost.
    let onReplace: () -> Void
    let onReplaceAll: () -> Void

    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            findRow
            replaceRow
            if let warning { costNotice(warning) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { isQueryFocused = true }
    }

    // MARK: - Find

    private var findRow: some View {
        HStack(spacing: 8) {
            TextField("Find in transcript", text: $controller.query)
                .textFieldStyle(.roundedBorder)
                .focused($isQueryFocused)
                .frame(maxWidth: .infinity)
                // Enter and Shift-Enter walk the matches, as they do everywhere
                // else on the platform.
                .onSubmit { controller.next() }

            Text(controller.summary)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(controller.hasMatches ? .secondary : .tertiary)
                .frame(minWidth: 76, alignment: .leading)

            Button {
                controller.previous()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!controller.hasMatches)
            .help("Previous match (⇧⌘G)")

            Button {
                controller.next()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!controller.hasMatches)
            .help("Next match (⌘G)")

            Button("Done") { controller.dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Replace

    private var replaceRow: some View {
        HStack(spacing: 8) {
            TextField("Replace with", text: $controller.replacement)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)

            Button("Replace", action: onReplace)
                .disabled(controller.current == nil)

            Button("Replace All", action: onReplaceAll)
                .disabled(!controller.hasMatches)
        }
    }

    /// What Replace All would cost, said before it is pressed rather than
    /// after.
    private var warning: String? {
        guard controller.hasMatches else { return nil }
        let dropping = controller.matchesThatWouldDropTimings()
        guard dropping > 0 else { return nil }

        let all = dropping == controller.matches.count
        return "\(all ? "All " : "")\(dropping) of \(controller.matches.count) "
            + "\(dropping == 1 ? "match spans" : "matches span") more than one word, "
            + "so replacing \(dropping == 1 ? "it" : "them") drops that line's word "
            + "timings and marks it edited."
    }

    private func costNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
