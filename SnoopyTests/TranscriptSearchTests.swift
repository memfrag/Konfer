//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// Finding text across a transcript, and replacing it without throwing away
/// the recording's word timings.
///
/// The timings are the part worth testing. They cannot be recovered once
/// dropped — only re-transcribing brings them back — so "fixing a name the
/// model misheard costs nothing" is a promise these tests hold to.
struct TranscriptSearchTests {

    // MARK: - Fixtures

    /// A turn whose words abut, as real word timings do.
    private func utterance(_ words: [String], from start: TimeInterval = 0) -> Utterance {
        let spans = words.enumerated().map { index, word in
            WordSpan(
                word: word,
                start: start + Double(index) * 0.5,
                end: start + Double(index + 1) * 0.5
            )
        }
        return Utterance(
            speakerId: "Speaker 1",
            start: start,
            end: start + Double(words.count) * 0.5,
            text: SpeakerAligner.joined(spans),
            words: spans
        )
    }

    private func meeting(_ utterances: [Utterance]) -> Meeting {
        Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 60,
            importedAt: Date(timeIntervalSince1970: 0),
            language: .english,
            speakers: [SpeakerLabel(id: "Speaker 1", name: "Anna")],
            utterances: utterances
        )
    }

    // MARK: - Finding

    @Test("A query with no match finds nothing")
    func noMatches() {
        let turns = [utterance(["the", "quarterly", "numbers"])]
        #expect(TranscriptSearch.matches(for: "revenue", in: turns).isEmpty)
    }

    @Test("An empty query finds nothing, rather than everything")
    func emptyQueryFindsNothing() {
        let turns = [utterance(["the", "quarterly", "numbers"])]
        #expect(TranscriptSearch.matches(for: "", in: turns).isEmpty)
        #expect(TranscriptSearch.matches(for: "   ", in: turns).isEmpty)
    }

    @Test("Matches come back in reading order, across turns")
    func matchesAreInReadingOrder() {
        let turns = [
            utterance(["Theresa", "opened"]),
            utterance(["then", "Theresa", "closed"], from: 10),
        ]
        let found = TranscriptSearch.matches(for: "theresa", in: turns)
        #expect(found.count == 2)
        #expect(found[0].utteranceID == turns[0].id)
        #expect(found[1].utteranceID == turns[1].id)
    }

    @Test("Searching ignores case and accents")
    func searchIgnoresCaseAndAccents() {
        // You search for a word precisely because you're unsure how the model
        // spelled it.
        let turns = [utterance(["hon", "åker", "hem"])]
        #expect(TranscriptSearch.matches(for: "AKER", in: turns).count == 1)
        #expect(TranscriptSearch.matches(for: "åker", in: turns).count == 1)
    }

    @Test("Every occurrence in one turn is found, including overlapping ones")
    func findsRepeatedAndOverlappingMatches() {
        let turns = [utterance(["aaa", "and", "aaa"])]
        // "aa" occurs twice in each "aaa", overlapping.
        #expect(TranscriptSearch.matches(for: "aa", in: turns).count == 4)
    }

    @Test("A match's offset points at the text it matched")
    func offsetsPointAtTheMatch() {
        let turns = [utterance(["the", "quarterly", "numbers"])]
        let match = try! #require(TranscriptSearch.matches(for: "quarterly", in: turns).first)
        let text = turns[0].text
        let start = text.index(text.startIndex, offsetBy: match.offset)
        let end = text.index(start, offsetBy: match.length)
        #expect(String(text[start..<end]) == "quarterly")
    }

    // MARK: - Where words sit in the text

    @Test("Word ranges line up with the text the words were joined into")
    func wordRangesMatchTheJoinedText() {
        let turn = utterance(["Right", ",", "shall", "we", "start", "?"])
        let text = turn.text
        for (index, range) in TranscriptSearch.wordRanges(in: turn.words ?? []) {
            let start = text.index(text.startIndex, offsetBy: range.lowerBound)
            let end = text.index(text.startIndex, offsetBy: range.upperBound)
            #expect(String(text[start..<end]) == turn.words?[index].word)
        }
    }

    @Test("A match inside one word knows which word it is in")
    func matchInsideAWordFindsIt() {
        let turn = utterance(["the", "quarterly", "numbers"])
        let match = try! #require(TranscriptSearch.matches(for: "quarter", in: [turn]).first)
        let word = TranscriptSearch.enclosingWord(of: match, in: turn.words ?? [])
        #expect(word?.index == 1)
    }

    @Test("A match spanning two words is inside neither")
    func matchAcrossWordsHasNoEnclosingWord() {
        let turn = utterance(["the", "quarterly", "numbers"])
        let match = try! #require(TranscriptSearch.matches(for: "the quarterly", in: [turn]).first)
        #expect(TranscriptSearch.enclosingWord(of: match, in: turn.words ?? []) == nil)
    }

    // MARK: - Replacing without losing timings

    @Test("Fixing a misheard name inside one word keeps that word's timings")
    func replacingInsideAWordKeepsTimings() throws {
        let turn = utterance(["Theresa", "opened", "the", "meeting"])
        var subject = meeting([turn])
        let before = try #require(turn.words)

        let match = try #require(
            TranscriptSearch.matches(for: "Theresa", in: subject.utterances).first
        )
        #expect(subject.replace(match, with: "Therese") == .keepsTimings)

        let after = try #require(subject.utterances[0].words)
        #expect(after.count == before.count)
        #expect(after[0].word == "Therese")
        #expect(after[0].start == before[0].start)
        #expect(after[0].end == before[0].end)
        // Every other word is untouched.
        #expect(Array(after.dropFirst()) == Array(before.dropFirst()))
    }

    @Test("A turn fixed this way is not marked as edited by hand")
    func replacingInsideAWordDoesNotMarkEdited() throws {
        var subject = meeting([utterance(["Theresa", "opened"])])
        let match = try #require(
            TranscriptSearch.matches(for: "Theresa", in: subject.utterances).first
        )
        subject.replace(match, with: "Therese")
        #expect(subject.utterances[0].isEdited == false)
    }

    @Test("The turn's text is rebuilt from its words, so the two cannot drift")
    func textStaysInStepWithWords() throws {
        var subject = meeting([utterance(["Theresa", "opened", "the", "meeting"])])
        let match = try #require(
            TranscriptSearch.matches(for: "Theresa", in: subject.utterances).first
        )
        subject.replace(match, with: "Therese")

        let words = try #require(subject.utterances[0].words)
        #expect(subject.utterances[0].text == SpeakerAligner.joined(words))
        #expect(subject.utterances[0].text == "Therese opened the meeting")
    }

    @Test("A replacement spanning two words drops the timings and says so")
    func replacingAcrossWordsDropsTimings() throws {
        var subject = meeting([utterance(["the", "quarterly", "numbers"])])
        let match = try #require(
            TranscriptSearch.matches(for: "the quarterly", in: subject.utterances).first
        )
        #expect(subject.replace(match, with: "those") == .dropsTimings)
        #expect(subject.utterances[0].words == nil)
        #expect(subject.utterances[0].isEdited)
        #expect(subject.utterances[0].text == "those numbers")
    }

    @Test("An already-edited turn can still be searched and replaced")
    func editedTurnsAreStillReplaceable() throws {
        var turn = utterance(["placeholder"])
        turn.words = nil
        turn.isEdited = true
        turn.text = "the numbers were wrong"
        var subject = meeting([turn])

        let match = try #require(
            TranscriptSearch.matches(for: "wrong", in: subject.utterances).first
        )
        #expect(subject.replace(match, with: "right") == .dropsTimings)
        #expect(subject.utterances[0].text == "the numbers were right")
    }

    @Test("A replacement that empties a word removes it rather than leaving a ghost")
    func emptyingAWordRemovesItsSpan() throws {
        var subject = meeting([utterance(["um", "the", "numbers"])])
        let match = try #require(
            TranscriptSearch.matches(for: "um", in: subject.utterances).first
        )
        subject.replace(match, with: "")

        let words = try #require(subject.utterances[0].words)
        #expect(words.count == 2)
        #expect(words.allSatisfy { !$0.word.isEmpty })
        #expect(subject.utterances[0].text == "the numbers")
    }

    @Test("A stale match, pointing past the end of the text, is refused")
    func staleMatchIsRefused() {
        var subject = meeting([utterance(["short"])])
        let stale = TranscriptMatch(
            utteranceID: subject.utterances[0].id, offset: 400, length: 5
        )
        #expect(subject.replace(stale, with: "x") == nil)
        #expect(subject.utterances[0].text == "short")
    }

    // MARK: - Replace all

    @Test("Replace all fixes every occurrence, in every turn")
    func replaceAllCoversEveryOccurrence() {
        var subject = meeting([
            utterance(["Theresa", "opened"]),
            utterance(["then", "Theresa", "spoke", "to", "Theresa"], from: 10),
        ])
        let result = subject.replaceAll("Theresa", with: "Therese")

        #expect(result.kept == 3)
        #expect(result.dropped == 0)
        #expect(TranscriptSearch.matches(for: "Theresa", in: subject.utterances).isEmpty)
        #expect(subject.utterances[1].text == "then Therese spoke to Therese")
    }

    @Test("Replace all keeps the timings of every turn it could")
    func replaceAllKeepsTimings() throws {
        var subject = meeting([
            utterance(["Theresa", "opened"]),
            utterance(["then", "Theresa", "spoke"], from: 10),
        ])
        subject.replaceAll("Theresa", with: "Therese")

        for turn in subject.utterances {
            #expect(turn.words != nil)
            #expect(turn.isEdited == false)
        }
    }

    @Test("Replace all reports what it cost, so the UI can warn before it runs")
    func replaceAllReportsTheCost() {
        var subject = meeting([
            utterance(["Theresa", "opened"]),
            utterance(["the", "quarterly", "numbers"], from: 10),
        ])
        // One inside a word, one spanning two.
        subject.replaceAll("Theresa", with: "Therese")
        let across = subject.replaceAll("the quarterly", with: "those")

        #expect(across.kept == 0)
        #expect(across.dropped == 1)
    }

    @Test("Replacing a word with a longer one doesn't corrupt later matches")
    func replaceAllHandlesGrowingText() {
        var subject = meeting([utterance(["ab", "ab", "ab"])])
        subject.replaceAll("ab", with: "abcdefgh")
        #expect(subject.utterances[0].text == "abcdefgh abcdefgh abcdefgh")
    }
}
