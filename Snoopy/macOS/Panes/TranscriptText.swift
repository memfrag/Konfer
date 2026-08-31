//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

// MARK: - Word token

/// A clickable run of transcript text.
///
/// Punctuation is folded into the word it follows, so a token is always
/// something a person would think of as a word — you never end up clicking a
/// lone comma, and the layout doesn't have to reason about which gaps get a
/// space.
struct WordToken: Identifiable {

    /// Index of the token's first `WordSpan`, which also identifies it.
    let id: Int
    let text: String
    let start: TimeInterval

    /// The word indices this token covers, for matching the playback highlight.
    let range: Range<Int>

    /// Where this token sits in the turn's text, in characters.
    ///
    /// Carried on the token so highlighting a search match is a comparison
    /// rather than a walk of every word for every token on every render.
    let textRange: Range<Int>

    /// The word being spoken at a given moment, or nil between words.
    ///
    /// `last`, not `first`: word timings abut, so at the exact instant a word
    /// begins both it and the one before it can qualify — the previous word's
    /// end and this word's start are the same number. The word just reached is
    /// the one meant, which is what makes clicking a word highlight *that*
    /// word.
    static func activeIndex(in words: [WordSpan], at time: TimeInterval) -> Int? {
        words.lastIndex {
            // A word with no duration — the models emit a few per hour — would
            // otherwise never match at all, so give it a brief window.
            time >= $0.start && time < max($0.end, $0.start + minimumWordWindow)
        }
    }

    /// Long enough to be reachable, short enough to be imperceptible.
    private static let minimumWordWindow: TimeInterval = 0.01

    static func tokens(from words: [WordSpan]) -> [WordToken] {
        var tokens: [WordToken] = []
        var offset = 0

        for (index, span) in words.enumerated() {
            let piece = span.word
            guard !piece.isEmpty else { continue }

            // The same joining rule the text itself was built with, so the
            // offsets describe `SpeakerAligner.joined(words)` exactly.
            let spacing = offset > 0 ? SpeakerAligner.spacing(before: piece).count : 0
            let start = offset + spacing
            offset = start + piece.count

            if !tokens.isEmpty, SpeakerAligner.spacing(before: piece).isEmpty {
                let previous = tokens.removeLast()
                tokens.append(
                    WordToken(
                        id: previous.id,
                        text: previous.text + piece,
                        start: previous.start,
                        range: previous.range.lowerBound..<(index + 1),
                        textRange: previous.textRange.lowerBound..<offset
                    )
                )
            } else {
                tokens.append(
                    WordToken(
                        id: index,
                        text: piece,
                        start: span.start,
                        range: index..<(index + 1),
                        textRange: start..<offset
                    )
                )
            }
        }
        return tokens
    }
}

// MARK: - Transcript text

/// Transcript text where clicking a word moves the playhead to it.
///
/// Text is deliberately not selectable here. Dragging to select and clicking to
/// seek are the same gesture, and seeking is what you want ninety-nine times
/// out of a hundred while checking a transcript against the audio. Selection
/// lives in edit mode, where it belongs.
struct TranscriptText: View {

    let tokens: [WordToken]
    let activeWordIndex: Int?

    let searchMatches: [TranscriptMatch]
    let currentSearchMatch: TranscriptMatch?

    /// Whether clicking a word should also offer what can be done at it.
    ///
    /// False while the audio is playing: the click is then a seek and nothing
    /// more, because a popover chasing the playhead would be in the way.
    let offersActions: Bool

    let onSeek: (TimeInterval) -> Void

    /// Splits the turn before the word at this index.
    let onSplitBefore: (Int) -> Void

    @State private var hovered: Int?

    /// The token whose popover is open, if any.
    @State private var actionToken: WordToken.ID?

    var body: some View {
        WrappingLines(spacing: 0, lineSpacing: 2) {
            ForEach(tokens) { token in
                Text(token.text)
                    .foregroundStyle(isActive(token) ? Color.accentColor : .primary)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(background(for: token))
                    )
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        hovered = isInside ? token.id : (hovered == token.id ? nil : hovered)
                    }
                    .onTapGesture {
                        onSeek(token.start)
                        actionToken = offersActions ? token.id : nil
                    }
                    .popover(
                        isPresented: Binding(
                            get: { actionToken == token.id },
                            set: { if !$0, actionToken == token.id { actionToken = nil } }
                        ),
                        arrowEdge: .bottom
                    ) {
                        actions(at: token)
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Play from here")
            }
        }
    }

    /// What can be done at the word just clicked.
    ///
    /// The playhead is already there — clicking moved it — so "before this
    /// word" and "at the playhead" name the same place.
    @ViewBuilder private func actions(at token: WordToken) -> some View {
        let wordIndex = token.range.lowerBound
        VStack(alignment: .leading, spacing: 0) {
            Button {
                actionToken = nil
                onSplitBefore(wordIndex)
            } label: {
                Label("Split before word", systemImage: "text.insert")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Nothing precedes the first word, so there is nothing to split off.
            .disabled(wordIndex == 0)

            if wordIndex == 0 {
                Text("This is the first word of the turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 180)
    }

    private func isActive(_ token: WordToken) -> Bool {
        guard let activeWordIndex else { return false }
        return token.range.contains(activeWordIndex)
    }

    /// Search matches tint whole tokens rather than the exact characters: a
    /// token is one clickable thing, and half of one lit is harder to read
    /// than all of it.
    private func background(for token: WordToken) -> Color {
        if let currentSearchMatch, covers(token, currentSearchMatch) {
            return .orange.opacity(0.55)
        }
        if searchMatches.contains(where: { covers(token, $0) }) {
            return .yellow.opacity(0.35)
        }
        return hovered == token.id ? Color.primary.opacity(0.08) : .clear
    }

    /// Whether a match falls anywhere in the characters this token covers.
    private func covers(_ token: WordToken, _ match: TranscriptMatch) -> Bool {
        token.textRange.lowerBound < match.range.upperBound
            && match.range.lowerBound < token.textRange.upperBound
    }
}

// MARK: - Wrapping layout

/// Lays subviews out left to right, wrapping to a new line when they run out
/// of width — what `Text` does for itself, but for views that need their own
/// hit testing.
struct WrappingLines: Layout {

    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 3

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let origin = arrangement.origins[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        subviews: Subviews,
        maxWidth: CGFloat
    ) -> (origins: [CGPoint], size: CGSize) {

        var origins: [CGPoint] = []
        origins.reserveCapacity(subviews.count)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                widestLine = max(widestLine, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        widestLine = max(widestLine, x - spacing)
        return (origins, CGSize(width: max(widestLine, 0), height: y + lineHeight))
    }
}
