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

    @Test("No words means no tokens")
    func noWordsMeansNoTokens() {
        #expect(WordToken.tokens(from: []).isEmpty)
    }
}
