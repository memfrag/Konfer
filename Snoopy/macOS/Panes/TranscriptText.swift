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

    static func tokens(from words: [WordSpan]) -> [WordToken] {
        var tokens: [WordToken] = []

        for (index, span) in words.enumerated() {
            let piece = span.word
            guard !piece.isEmpty else { continue }

            if !tokens.isEmpty, SpeakerAligner.spacing(before: piece).isEmpty {
                let previous = tokens.removeLast()
                tokens.append(
                    WordToken(
                        id: previous.id,
                        text: previous.text + piece,
                        start: previous.start,
                        range: previous.range.lowerBound..<(index + 1)
                    )
                )
            } else {
                tokens.append(
                    WordToken(
                        id: index,
                        text: piece,
                        start: span.start,
                        range: index..<(index + 1)
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
    let onSeek: (TimeInterval) -> Void

    @State private var hovered: Int?

    var body: some View {
        WrappingLines(spacing: 0, lineSpacing: 2) {
            ForEach(tokens) { token in
                Text(token.text)
                    .foregroundStyle(isActive(token) ? Color.accentColor : .primary)
                    .padding(.horizontal, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(hovered == token.id ? Color.primary.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onHover { isInside in
                        hovered = isInside ? token.id : (hovered == token.id ? nil : hovered)
                    }
                    .onTapGesture { onSeek(token.start) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Play from here")
            }
        }
    }

    private func isActive(_ token: WordToken) -> Bool {
        guard let activeWordIndex else { return false }
        return token.range.contains(activeWordIndex)
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
