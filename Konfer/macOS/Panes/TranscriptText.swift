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
struct WordToken: Identifiable, Equatable {

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
/// One `Text` per turn, with the words found again afterwards in its layout.
/// It used to be one view per word, each with its own hover, tap and popover,
/// which made a screenful of transcript a few thousand views. Measured on five
/// real meetings in a debug build: building the list fell from 190 ms to 90,
/// and the frame that tears the previous meeting's down from 100 ms to 63.
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

    @State private var hovered: WordToken.ID?

    /// The token whose popover is open, if any.
    @State private var actionToken: WordToken.ID?

    var body: some View {
        // Equatable, so that the pointer crossing a word redraws a highlight
        // rather than laying the whole turn out again.
        let string = TokenString(tokens)
        TokenText(tokens: string, activeTokenID: activeTokenID)
            .equatable()
            .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                let highlights = highlights
                if !highlights.isEmpty {
                    GeometryReader { proxy in
                        let frames = TokenFrames(layouts, of: string, in: proxy)
                        Canvas { context, _ in
                            for (id, color) in highlights {
                                for rect in frames[id] {
                                    context.fill(
                                        Path(roundedRect: rect, cornerRadius: 3),
                                        with: .color(color)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    interaction(TokenFrames(layouts, of: string, in: proxy))
                }
            }
    }

    /// Where the pointer and the clicks go.
    ///
    /// A clear layer over the text rather than gestures on the text itself,
    /// because only here are the words' frames at hand to say which one was
    /// hit — and it is one popover for the turn instead of one per word.
    private func interaction(_ frames: TokenFrames) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                let id: WordToken.ID? = switch phase {
                case .active(let location): frames.token(at: location)
                case .ended: nil
                }
                if id != hovered { hovered = id }
            }
            .onTapGesture { location in
                guard let id = frames.token(at: location),
                      let token = tokens.first(where: { $0.id == id })
                else { return }
                onSeek(token.start)
                actionToken = offersActions ? id : nil
            }
            .popover(
                isPresented: Binding(
                    get: { actionToken != nil },
                    set: { if !$0 { actionToken = nil } }
                ),
                attachmentAnchor: .rect(.rect(actionToken.flatMap { frames[$0].first } ?? .zero)),
                arrowEdge: .bottom
            ) {
                if let token = tokens.first(where: { $0.id == actionToken }) {
                    actions(at: token)
                }
            }
            // The text underneath is what an assistive app should read.
            .accessibilityHidden(true)
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

    private var activeTokenID: WordToken.ID? {
        guard let activeWordIndex else { return nil }
        return tokens.first { $0.range.contains(activeWordIndex) }?.id
    }

    /// The tokens drawn with a background, and in what.
    ///
    /// Search matches tint whole tokens rather than the exact characters: a
    /// token is one clickable thing, and half of one lit is harder to read
    /// than all of it.
    private var highlights: [(WordToken.ID, Color)] {
        var highlights: [(WordToken.ID, Color)] = []
        if !searchMatches.isEmpty {
            for token in tokens {
                if let currentSearchMatch, covers(token, currentSearchMatch) {
                    highlights.append((token.id, .orange.opacity(0.55)))
                } else if searchMatches.contains(where: { covers(token, $0) }) {
                    highlights.append((token.id, .yellow.opacity(0.35)))
                }
            }
        }
        if let hovered, !highlights.contains(where: { $0.0 == hovered }) {
            highlights.append((hovered, Color.primary.opacity(0.08)))
        }
        return highlights
    }

    /// Whether a match falls anywhere in the characters this token covers.
    private func covers(_ token: WordToken, _ match: TranscriptMatch) -> Bool {
        token.textRange.lowerBound < match.range.upperBound
            && match.range.lowerBound < token.textRange.upperBound
    }
}

// MARK: - Token string

/// A turn's words laid end to end, and where each one landed.
///
/// One string rather than a `Text` per word interpolated together: resolving
/// that interpolation scans it as a localization format and builds an
/// attributed string per word, which measured as costly as the separate views
/// it replaced.
private struct TokenString: Equatable {

    let string: String
    let ids: [WordToken.ID]

    /// Each token's place in ``string``, in UTF-16 code units — the unit
    /// `Text.Layout` counts characters in.
    let ranges: [Range<Int>]

    init(_ tokens: [WordToken]) {
        var string = ""
        var ranges: [Range<Int>] = []
        var offset = 0
        var end = 0
        for token in tokens {
            // The gap `WordToken.tokens` left between the two, which is the
            // same joining rule the turn's text was built with.
            let gap = token.textRange.lowerBound - end
            if gap > 0 {
                string += String(repeating: " ", count: gap)
                offset += gap
            }
            string += token.text
            let length = token.text.utf16.count
            ranges.append(offset..<(offset + length))
            offset += length
            end = token.textRange.upperBound
        }
        self.string = string
        self.ids = tokens.map(\.id)
        self.ranges = ranges
    }

    /// The token at a UTF-16 offset, or nil in the space between two.
    func token(at offset: Int) -> WordToken.ID? {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = (low + high) / 2
            if ranges[middle].upperBound <= offset {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < ranges.count, ranges[low].contains(offset) else { return nil }
        return ids[low]
    }

    func range(of id: WordToken.ID) -> Range<Int>? {
        ids.firstIndex(of: id).map { ranges[$0] }
    }
}

// MARK: - Token text

/// The turn as a single `Text`, with the word being spoken in the accent
/// colour.
private struct TokenText: View, Equatable {

    let tokens: TokenString
    let activeTokenID: WordToken.ID?

    var body: some View {
        text
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: Text {
        guard let activeTokenID, let range = tokens.range(of: activeTokenID) else {
            return Text(verbatim: tokens.string)
        }
        let string = tokens.string
        let lower = String.Index(utf16Offset: range.lowerBound, in: string)
        let upper = String.Index(utf16Offset: range.upperBound, in: string)
        var active = AttributedString(string[lower..<upper])
        active.foregroundColor = .accentColor
        return Text(
            AttributedString(string[..<lower]) + active + AttributedString(string[upper...])
        )
    }
}

// MARK: - Token frames

/// Where each token was drawn, read back out of the text's layout.
private struct TokenFrames {

    /// Usually one rectangle; more when a word too long for the line wraps.
    private var rects: [WordToken.ID: [CGRect]] = [:]

    init(_ layouts: Text.LayoutKey.Value, of tokens: TokenString, in proxy: GeometryProxy) {
        for anchored in layouts {
            let origin = proxy[anchored.origin]

            // `CharacterIndex` keeps its offset to itself, so offsets are
            // measured from the lowest index in the layout — the first
            // character, which always gets a glyph slice even when it draws
            // nothing.
            var glyphs: [(line: Int, index: Text.Layout.CharacterIndex, rect: CGRect)] = []
            for (number, line) in anchored.layout.enumerated() {
                for run in line {
                    for glyph in run {
                        guard let index = glyph.characterIndices.first else { continue }
                        glyphs.append((number, index, glyph.typographicBounds.rect))
                    }
                }
            }
            guard let base = glyphs.map(\.index).min() else { continue }

            // Consecutive glyphs of one token on one line become one rectangle.
            var current: (id: WordToken.ID, line: Int, rect: CGRect)?
            func close() {
                guard let current else { return }
                // Widened into the spaces either side, so the highlight has a
                // margin and a click between two words still lands on one.
                let rect = current.rect
                    .offsetBy(dx: origin.x, dy: origin.y)
                    .insetBy(dx: -2, dy: 0)
                rects[current.id, default: []].append(rect)
            }
            for glyph in glyphs {
                guard let id = tokens.token(at: base.distance(to: glyph.index)) else {
                    close()
                    current = nil
                    continue
                }
                if let open = current, open.id == id, open.line == glyph.line {
                    current?.rect = open.rect.union(glyph.rect)
                } else {
                    close()
                    current = (id, glyph.line, glyph.rect)
                }
            }
            close()
        }
    }

    subscript(id: WordToken.ID) -> [CGRect] {
        rects[id] ?? []
    }

    func token(at point: CGPoint) -> WordToken.ID? {
        rects.first { $0.value.contains { $0.contains(point) } }?.key
    }
}
