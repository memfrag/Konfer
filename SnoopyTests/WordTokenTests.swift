//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// Clicking a word seeks to it, so the tokens have to line up with what a
/// person would call a word — and each has to carry the right start time.
@MainActor
struct WordTokenTests {

    private func word(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> WordSpan {
        WordSpan(word: text, start: start, end: end)
    }

    @Test("Each word becomes its own token")
    func plainWordsBecomeTokens() {
        let tokens = WordToken.tokens(from: [
            word("Hej", 0, 0.3),
            word("du", 0.4, 0.6)
        ])

        #expect(tokens.map(\.text) == ["Hej", "du"])
        #expect(tokens.map(\.start) == [0, 0.4])
    }

    @Test("Punctuation folds into the word it follows")
    func punctuationFoldsIntoPreviousWord() {
        let tokens = WordToken.tokens(from: [
            word("Hej", 0, 0.3),
            word(",", 0.3, 0.35),
            word("du", 0.4, 0.6),
            word(".", 0.6, 0.65)
        ])

        // You should never be able to click a lone comma.
        #expect(tokens.map(\.text) == ["Hej,", "du."])
        #expect(tokens.map(\.start) == [0, 0.4])
    }

    @Test("A folded token keeps the start time of its first word")
    func foldedTokenKeepsFirstStart() {
        let tokens = WordToken.tokens(from: [
            word("ja", 5.0, 5.4),
            word("!", 5.4, 5.5)
        ])

        #expect(tokens.count == 1)
        #expect(tokens[0].start == 5.0)
    }

    @Test("A token covers every word index it swallowed, for highlighting")
    func tokenRangeCoversFoldedWords() {
        let tokens = WordToken.tokens(from: [
            word("Hej", 0, 0.3),
            word(",", 0.3, 0.35),
            word("du", 0.4, 0.6)
        ])

        #expect(tokens[0].range == 0..<2)
        #expect(tokens[1].range == 2..<3)
    }

    @Test("Leading punctuation with nothing before it stands on its own")
    func leadingPunctuationSurvives() {
        let tokens = WordToken.tokens(from: [word(",", 0, 0.1), word("du", 0.2, 0.4)])

        #expect(tokens.map(\.text) == [",", "du"])
    }

    @Test("Empty words are dropped")
    func emptyWordsAreDropped() {
        let tokens = WordToken.tokens(from: [
            word("Hej", 0, 0.3),
            word("", 0.3, 0.3),
            word("du", 0.4, 0.6)
        ])

        #expect(tokens.map(\.text) == ["Hej", "du"])
    }

    // MARK: - Which word is highlighted

    /// Word timings abut: one word's end is the next word's start, for 85–95%
    /// of adjacent pairs in real transcripts. Clicking a word used to seek a
    /// fraction before it — `CMTime` rounding to the nearest 1/600 s landed
    /// nearly a third of word starts up to 0.8 ms early — and the lookup then
    /// reported the *previous* word, because it also matched.

    @Test("The word starting at this exact instant wins over the one ending at it")
    func boundaryPrefersTheWordJustReached() {
        let words = [
            WordSpan(word: "one", start: 0, end: 1),
            WordSpan(word: "two", start: 1, end: 2),
        ]
        #expect(WordToken.activeIndex(in: words, at: 1) == 1)
    }

    @Test("Clicking a word highlights that word, not its predecessor")
    func clickingAWordHighlightsIt() {
        let words = (0..<5).map {
            WordSpan(word: "w\($0)", start: Double($0) * 0.5, end: Double($0 + 1) * 0.5)
        }
        for (index, word) in words.enumerated() {
            #expect(WordToken.activeIndex(in: words, at: word.start) == index)
        }
    }

    @Test("A word is still the active one partway through it")
    func midWordStaysOnTheWord() {
        let words = [
            WordSpan(word: "one", start: 0, end: 1),
            WordSpan(word: "two", start: 1, end: 2),
        ]
        #expect(WordToken.activeIndex(in: words, at: 0.5) == 0)
        #expect(WordToken.activeIndex(in: words, at: 1.9) == 1)
    }

    @Test("A word with no duration can still be reached")
    func zeroLengthWordIsReachable() {
        // The models emit a few of these per hour — 43 in one real Danish
        // transcript — and a strictly-inside test could never match them.
        let words = [
            WordSpan(word: "one", start: 0, end: 1),
            WordSpan(word: "blip", start: 1, end: 1),
            WordSpan(word: "two", start: 2, end: 3),
        ]
        #expect(WordToken.activeIndex(in: words, at: 1) == 1)
    }

    @Test("Nothing is highlighted before the first word or in a gap")
    func gapsHighlightNothing() {
        let words = [
            WordSpan(word: "one", start: 1, end: 2),
            WordSpan(word: "two", start: 5, end: 6),
        ]
        #expect(WordToken.activeIndex(in: words, at: 0.5) == nil)
        #expect(WordToken.activeIndex(in: words, at: 3) == nil)
        #expect(WordToken.activeIndex(in: words, at: 9) == nil)
    }

    @Test("No words means no tokens")
    func noWordsMeansNoTokens() {
        #expect(WordToken.tokens(from: []).isEmpty)
    }
}
