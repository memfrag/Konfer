//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The video export writes a subtitle track by hand, so the two things worth
/// pinning down without a video file are the sample encoding and the promise
/// that an embedded cue says exactly what the SubRip one says.
@MainActor
struct SubtitledVideoTests {

    // MARK: - tx3g samples

    @Test("A tx3g sample is its UTF-8 length in two bytes, then the text")
    func payloadCarriesLengthThenText() {
        let data = SubtitledVideoWriter.payload(for: "Hej")

        #expect(Array(data) == [0x00, 0x03, 0x48, 0x65, 0x6A])
    }

    @Test("The length is the byte count, not the character count")
    func payloadCountsBytes() {
        // "Björn" is five characters and six UTF-8 bytes.
        let data = SubtitledVideoWriter.payload(for: "Björn")

        #expect(data.count == 8)
        #expect(Array(data.prefix(2)) == [0x00, 0x06])
        #expect(String(data: data.dropFirst(2), encoding: .utf8) == "Björn")
    }

    @Test("An empty sample is the two zero bytes alone")
    func emptyPayloadIsTwoZeroBytes() {
        // These fill the gaps between cues; a subtitle track with holes in it
        // is a common reason for nothing appearing at all.
        #expect(Array(SubtitledVideoWriter.payload(for: "")) == [0x00, 0x00])
    }

    @Test("A cue longer than a 16-bit length is truncated rather than mis-sized")
    func payloadClampsToSixteenBits() {
        let data = SubtitledVideoWriter.payload(for: String(repeating: "a", count: 70_000))
        let declared = Int(data[0]) << 8 | Int(data[1])

        #expect(declared == Int(UInt16.max))
        #expect(data.count == 2 + Int(UInt16.max))
    }

    // MARK: - The same words as SubRip

    @Test("An embedded cue says exactly what the SubRip file says")
    func embeddedTextMatchesSubRip() throws {
        let words = "Right shall we start I think everyone is here now and we have a lot to get through"
            .split(separator: " ")
        var spans: [WordSpan] = []
        var clock: TimeInterval = 0
        for word in words {
            spans.append(WordSpan(word: String(word), start: clock, end: clock + 0.4))
            clock += 0.4
        }
        let meeting = Meeting(
            id: UUID(), title: "Standup", audioPath: "/tmp/standup.mov",
            duration: 60, importedAt: Date(), language: .english,
            speakers: [SpeakerLabel(id: "A", name: "Anna")],
            utterances: [Utterance(
                speakerId: "A", start: 0, end: clock,
                text: words.joined(separator: " "), words: spans
            )]
        )

        let srt = try #require(
            String(data: try TranscriptExporter.data(for: meeting, format: .subRip), encoding: .utf8)
        )
        let cues = SubtitleExporter.cues(for: meeting, attributionTakesRoom: true)

        #expect(cues.count > 1, "the fixture should be long enough to split")
        for cue in cues {
            // Exactly the text the writer puts in the tx3g sample.
            #expect(srt.contains(SubtitleExporter.displayText(for: cue)))
        }
    }

    // MARK: - The queue

    @Test("A finished export reports where it put the file")
    func queueReportsFinished() async throws {
        let queue = VideoExportQueue { _, url, _, progress in
            progress(0.5)
            _ = url
        }
        let destination = URL(fileURLWithPath: "/tmp/konfer-test-export.mov")

        queue.export(makeMeeting(), to: destination, trimmed: false)
        try await settle { queue.state == .finished(destination) }

        #expect(queue.state == .finished(destination))
    }

    @Test("A failed export surfaces why, in words")
    func queueReportsFailure() async throws {
        let queue = VideoExportQueue { _, _, _, _ in
            throw VideoExportError.notAVideo(URL(fileURLWithPath: "/tmp/standup.wav"))
        }

        queue.export(makeMeeting(), to: URL(fileURLWithPath: "/tmp/x.mov"), trimmed: false)
        try await settle { if case .failed = queue.state { return true } else { return false } }

        guard case .failed(let message) = queue.state else {
            Issue.record("expected a failure, got \(queue.state)")
            return
        }
        #expect(message.contains("no video"))
        #expect(message.contains("audio only"), "the recovery suggestion is the useful half")
    }

    @Test("Only one export runs at a time")
    func queueRefusesASecondExport() async throws {
        let queue = VideoExportQueue { _, _, _, _ in
            try await Task.sleep(for: .seconds(5))
        }
        let first = URL(fileURLWithPath: "/tmp/first.mov")

        queue.export(makeMeeting(), to: first, trimmed: false)
        try await settle { queue.state.isExporting }
        queue.export(makeMeeting(), to: URL(fileURLWithPath: "/tmp/second.mov"), trimmed: false)

        #expect(queue.title == "Standup")
        #expect(queue.state.isExporting)
        queue.cancel()
    }

    @Test("Cancelling leaves the queue idle rather than failed")
    func cancellingIsNotAFailure() async throws {
        let queue = VideoExportQueue { _, _, _, _ in
            try await Task.sleep(for: .seconds(5))
        }

        queue.export(makeMeeting(), to: URL(fileURLWithPath: "/tmp/x.mov"), trimmed: false)
        try await settle { queue.state.isExporting }
        queue.cancel()
        try await settle { queue.state == .idle }

        #expect(queue.state == .idle)
    }

    // MARK: - Helpers

    private func makeMeeting() -> Meeting {
        Meeting(
            id: UUID(), title: "Standup", audioPath: "/tmp/standup.mov",
            duration: 60, importedAt: Date(), language: .english,
            speakers: [SpeakerLabel(id: "A", name: "Anna")],
            utterances: [Utterance(speakerId: "A", start: 0, end: 2, text: "Hej")]
        )
    }

    /// The queue hops through the main actor to publish, so a test has to let
    /// those hops land rather than reading the state on the next line.
    private func settle(
        until condition: () -> Bool,
        within limit: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition never became true")
    }
}
