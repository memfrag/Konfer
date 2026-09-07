//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Subtitles are the one export that reshapes the transcript rather than
/// restating it: a turn becomes several cues, cut at the model's own word
/// timings. Where those cuts land, and what happens to a turn that has no
/// timings left, is the whole of it.
@MainActor
struct SubtitleExporterTests {

    // MARK: - Fixtures

    private func words(
        _ text: String,
        from start: TimeInterval,
        each: TimeInterval
    ) -> [WordSpan] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin: TimeInterval = start + Double(index) * each
            return WordSpan(word: String(word), start: begin, end: begin + each)
        }
    }

    private func meeting(_ utterances: [Utterance], keptRange: KeptRange? = nil) -> Meeting {
        Meeting(
            id: UUID(),
            title: "Standup",
            audioPath: "/tmp/standup.m4a",
            duration: 600,
            importedAt: Date(),
            language: .english,
            speakers: [
                SpeakerLabel(id: "A", name: "Anna"),
                SpeakerLabel(id: "B", name: "Björn")
            ],
            utterances: utterances,
            keptRange: keptRange
        )
    }

    private func turn(
        speaker: String,
        text: String,
        from start: TimeInterval,
        each: TimeInterval = 0.4
    ) -> Utterance {
        let spans = words(text, from: start, each: each)
        return Utterance(
            speakerId: speaker,
            start: spans.first?.start ?? start,
            end: spans.last?.end ?? start,
            text: text,
            words: spans
        )
    }

    // MARK: - Timestamps

    @Test("Subtitle timestamps carry milliseconds, with the format's separator")
    func timestampFormatting() {
        #expect(Timecode.subtitle(0, decimalSeparator: ".") == "00:00:00.000")
        #expect(Timecode.subtitle(4.12, decimalSeparator: ".") == "00:00:04.120")
        #expect(Timecode.subtitle(4.12, decimalSeparator: ",") == "00:00:04,120")
        #expect(Timecode.subtitle(3725.5, decimalSeparator: ".") == "01:02:05.500")
    }

    @Test("A time a hair under a second rounds up rather than to 1000 milliseconds")
    func timestampRounding() {
        #expect(Timecode.subtitle(6.9999, decimalSeparator: ".") == "00:00:07.000")
    }

    // MARK: - Cues

    @Test("A short turn is one cue, attributed to its speaker")
    func shortTurnIsOneCue() {
        let cues = SubtitleExporter.cues(
            for: meeting([turn(speaker: "A", text: "Right, shall we start.", from: 4)])
        )

        #expect(cues.count == 1)
        #expect(cues[0].speaker == "Anna")
        #expect(cues[0].text == "Right, shall we start.")
        #expect(cues[0].start == 4)
    }

    @Test("A long turn is cut into cues at word boundaries")
    func longTurnSplits() {
        let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let cues = SubtitleExporter.cues(
            for: meeting([turn(speaker: "A", text: text, from: 0)])
        )

        #expect(cues.count > 1)
        for cue in cues {
            #expect(cue.text.count <= SubtitleExporter.maximumCharacters)
            #expect(cue.end - cue.start <= SubtitleExporter.maximumDuration + 0.5)
        }
        // Every word survives the cutting, in order and unduplicated.
        #expect(cues.map(\.text).joined(separator: " ") == text)
    }

    /// The guarantee that matters is about what ends up on screen, not about
    /// the cue before a format has laid it out. SubRip in particular puts the
    /// speaker's name on the same line as the words, and measuring the speech
    /// alone once let a 47-character line through.
    @Test("No rendered subtitle line is wider than a line is read at", arguments: [
        TranscriptExporter.Format.webVTT, .subRip
    ])
    func renderedLinesFitTheirWidth(format: TranscriptExporter.Format) throws {
        let long = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let sample = meeting([
            turn(speaker: "A", text: long, from: 0),
            turn(speaker: "B", text: "A short one.", from: 60)
        ])

        let text = try #require(
            String(data: try TranscriptExporter.data(for: sample, format: format), encoding: .utf8)
        )

        for block in text.components(separatedBy: "\n\n") where block.contains("-->") {
            let body = block.split(separator: "\n").drop { !$0.contains("-->") }.dropFirst()
            #expect(body.count <= SubtitleExporter.maximumLines, "cue has too many lines:\n\(block)")
            for line in body {
                // The voice tag is markup, not something anybody reads.
                let visible = line.replacingOccurrences(
                    of: "<v [^>]*>", with: "", options: .regularExpression
                )
                #expect(
                    visible.count <= SubtitleExporter.maximumLineLength,
                    "\(visible.count) characters: \(visible)"
                )
            }
        }
    }

    @Test("A speaker is named once per turn, not once per cue")
    func speakerNamedOncePerTurn() {
        let text = (0..<40).map { "word\($0)" }.joined(separator: " ")
        let cues = SubtitleExporter.cues(
            for: meeting([turn(speaker: "A", text: text, from: 0)])
        )

        #expect(cues.first?.speaker == "Anna")
        #expect(cues.dropFirst().allSatisfy { $0.speaker == nil })
    }

    @Test("A hand-edited turn goes out whole rather than split on invented times")
    func editedTurnIsOneCue() {
        var edited = turn(speaker: "A", text: "one two three", from: 0)
        edited.words = nil
        edited.text = (0..<40).map { "word\($0)" }.joined(separator: " ")

        let cues = SubtitleExporter.cues(for: meeting([edited]))

        #expect(cues.count == 1)
        #expect(cues[0].start == edited.start)
        #expect(cues[0].end == edited.end)
    }

    @Test("Trimmed turns are left out of subtitles too")
    func trimmedTurnsExcluded() {
        let kept = KeptRange(start: 50, end: 100)
        let cues = SubtitleExporter.cues(for: meeting(
            [
                turn(speaker: "A", text: "Before the trim.", from: 10),
                turn(speaker: "B", text: "Inside the trim.", from: 60)
            ],
            keptRange: kept
        ))

        #expect(cues.count == 1)
        #expect(cues[0].speaker == "Björn")
    }

    // MARK: - WebVTT

    @Test("WebVTT has its header, dotted timestamps and a voice tag")
    func webVTTShape() {
        let vtt = SubtitleExporter.webVTT(
            for: meeting([turn(speaker: "A", text: "Right, shall we start.", from: 4)])
        )

        #expect(vtt.hasPrefix("WEBVTT\n"))
        #expect(vtt.contains("00:00:04.000 --> "))
        #expect(vtt.contains("<v Anna>Right, shall we start."))

        // The separator is the only thing distinguishing these timestamps from
        // SubRip's, so check the timing line rather than the file: the speech
        // itself is full of commas.
        let timing = try? #require(
            vtt.split(separator: "\n").first { $0.contains("-->") }
        )
        #expect(timing?.contains(".") == true)
        #expect(timing?.contains(",") == false)
    }

    @Test("Angle brackets in speech can't swallow the rest of a WebVTT cue")
    func webVTTEscapes() {
        let vtt = SubtitleExporter.webVTT(
            for: meeting([turn(speaker: "A", text: "a < b & c", from: 0)])
        )

        #expect(vtt.contains("a &lt; b &amp; c"))
        #expect(!vtt.contains("a < b"))
    }

    // MARK: - SubRip

    @Test("SubRip is numbered from one, with comma timestamps and a named speaker")
    func srtShape() {
        let srt = SubtitleExporter.srt(for: meeting([
            turn(speaker: "A", text: "Right, shall we start.", from: 4),
            turn(speaker: "B", text: "Go ahead.", from: 12)
        ]))
        let blocks = srt.components(separatedBy: "\n\n").filter { !$0.isEmpty }

        #expect(blocks.count == 2)
        #expect(blocks[0].hasPrefix("1\n"))
        #expect(blocks[1].hasPrefix("2\n"))
        #expect(srt.contains("00:00:04,000 --> "))
        #expect(srt.contains("Anna: Right, shall we start."))
        #expect(srt.contains("Björn: Go ahead."))
    }

    // MARK: - Through the exporter

    @Test("Both subtitle formats come out of the exporter as UTF-8")
    func exporterProducesBothFormats() throws {
        let sample = meeting([turn(speaker: "A", text: "Hello there.", from: 1)])

        for format in [TranscriptExporter.Format.webVTT, .subRip] {
            let data = try TranscriptExporter.data(for: sample, format: format)
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(text.contains("Hello there."))
            #expect(!text.isEmpty)
        }

        #expect(TranscriptExporter.Format.webVTT.fileExtension == "vtt")
        #expect(TranscriptExporter.Format.subRip.fileExtension == "srt")
    }
}
