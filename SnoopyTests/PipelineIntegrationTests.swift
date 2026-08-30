//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// End-to-end check against the real models.
///
/// Disabled by default: the first run downloads several hundred megabytes from
/// Hugging Face, so this has no business in an ordinary test pass. Enable it by
/// setting `SNOOPY_AUDIO` to a recording:
///
///     SNOOPY_AUDIO=/path/to/meeting.m4a \
///       xcodebuild test -scheme "Snoopy (Debug)" \
///       -only-testing:SnoopyTests/PipelineIntegrationTests
///
/// It checks that the pipeline produces a speaker-attributed, timestamped
/// transcript at all — not how accurate that transcript is. Accuracy has to be
/// judged by ear against a real recording.
///
@MainActor
struct PipelineIntegrationTests {

    nonisolated static var audioURL: URL? {
        ProcessInfo.processInfo.environment["SNOOPY_AUDIO"]
            .map { URL(fileURLWithPath: $0) }
    }

    /// Set `SNOOPY_LIBRARY=real` to write the result into the app's actual
    /// library instead of a throwaway directory, so the transcript can be
    /// opened in Snoopy afterwards. Off by default — tests should not touch
    /// the user's data.
    /// `SNOOPY_BACKEND=parakeet|kb-whisper-small|kb-whisper-large` picks the
    /// model; defaults to whatever the app defaults to.
    nonisolated static var backend: ASRBackendKind {
        ProcessInfo.processInfo.environment["SNOOPY_BACKEND"]
            .flatMap(ASRBackendKind.init(rawValue:)) ?? .default
    }

    /// `SNOOPY_LANGUAGE=auto|swedish|english` tags the meeting, which is what
    /// routes `.automatic` between Apple Speech and KB-Whisper.
    nonisolated static var language: MeetingLanguage {
        ProcessInfo.processInfo.environment["SNOOPY_LANGUAGE"]
            .flatMap(MeetingLanguage.init(rawValue:)) ?? .auto
    }

    nonisolated static var usesRealLibrary: Bool {
        ProcessInfo.processInfo.environment["SNOOPY_LIBRARY"] == "real"
    }

    @Test(
        "Transcribes a real recording into speaker-attributed turns",
        .enabled(if: PipelineIntegrationTests.audioURL != nil),
        .timeLimit(.minutes(30))
    )
    func transcribesRealAudio() async throws {
        let url = try #require(Self.audioURL)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnoopyIntegration-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let meetingStore = Self.usesRealLibrary
            ? MeetingStore()
            : MeetingStore(directory: scratch)
        let speakerStore = Self.usesRealLibrary
            ? SpeakerStore()
            : SpeakerStore(directory: scratch)

        let pipeline = TranscriptionPipeline(
            diarizer: DiarizationService(),
            meetingStore: meetingStore,
            speakerStore: speakerStore
        )
        pipeline.selectedBackend = Self.backend
        pipeline.fastTranscription =
            ProcessInfo.processInfo.environment["SNOOPY_FAST"] == "1"
        print("backend: \(Self.backend.resolved(for: Self.language).rawValue) (language: \(Self.language.rawValue))")

        // Sample the stage as it changes, so the run reports where the time
        // actually went rather than one opaque total.
        var reached99: Date?
        var lastReportedBucket = -1
        var stageDurations: [String: TimeInterval] = [:]
        var currentStage = pipeline.stage.label
        var stageStarted = Date()
        let runStarted = Date()

        pipeline.enqueue(url, language: Self.language)

        var lastTick = Date()
        var worstStall: TimeInterval = 0
        var stalls: [TimeInterval] = []

        while pipeline.isRunning {
            try await Task.sleep(for: .milliseconds(250))
            // How late did this main-actor tick actually arrive? A blocked main
            // thread shows up here as an interval far longer than it asked for.
            let interval = Date().timeIntervalSince(lastTick)
            lastTick = Date()
            if interval > 0.75 {
                stalls.append(interval)
                worstStall = max(worstStall, interval)
            }
            let label = pipeline.stage.label
            if label == "Transcribing", let fraction = pipeline.stage.fraction {
                if fraction >= 0.99, reached99 == nil { reached99 = Date() }
                let bucket = Int(fraction * 10)
                if bucket > lastReportedBucket {
                    lastReportedBucket = bucket
                    print(String(format: "  transcribing %.0f%%", fraction * 100))
                }
            }
            if label != currentStage {
                stageDurations[currentStage, default: 0] += Date().timeIntervalSince(stageStarted)
                currentStage = label
                stageStarted = Date()
            }
        }
        stageDurations[currentStage, default: 0] += Date().timeIntervalSince(stageStarted)
        let totalSeconds = Date().timeIntervalSince(runStarted)
        if !stalls.isEmpty {
            print(String(
                format: "  MAIN THREAD stalled %d times, worst %.1fs, total %.1fs",
                stalls.count, worstStall, stalls.reduce(0, +)
            ))
        } else {
            print("  main thread never stalled")
        }
        if let reached99 {
            print(String(format: "  stuck at 99%% for %.1fs",
                         Date().timeIntervalSince(reached99)))
        }

        #expect(pipeline.lastError == nil, "\(String(describing: pipeline.lastError))")

        let meeting = try #require(meetingStore.meetings.first)
        #expect(!meeting.utterances.isEmpty)
        #expect(meeting.duration > 0)

        // Every turn must resolve to a speaker on the roster, be non-empty, and
        // sit inside the recording.
        for utterance in meeting.utterances {
            #expect(!utterance.text.isEmpty)
            #expect(meeting.speaker(utterance.speakerId) != nil)
            #expect(utterance.start >= 0)
            #expect(utterance.end <= meeting.duration + 1)
            #expect(utterance.start <= utterance.end)
        }

        // Turns must come out in transcript order.
        for (previous, next) in zip(meeting.utterances, meeting.utterances.dropFirst()) {
            #expect(previous.start <= next.start)
        }

        // Enough of a report to eyeball the result in the test log.
        print("--- TIMING ---")
        print(String(format: "audio: %.0fs", meeting.duration))
        for (stage, seconds) in stageDurations.sorted(by: { $0.value > $1.value }) {
            print(String(format: "%@: %.1fs", stage, seconds))
        }
        print(String(
            format: "total: %.1fs (%.0fx real time)",
            totalSeconds,
            meeting.duration / max(totalSeconds, 0.001)
        ))
        let words = meeting.utterances.flatMap { $0.words ?? [] }
        let spoken = words.reduce(0.0) { $0 + ($1.end - $1.start) }
        let covered = meeting.utterances.reduce(0.0) { $0 + $1.duration }
        print(String(
            format: "words: %d  word-seconds: %.0f  turn-seconds: %.0f of %.0f (%.0f%%)",
            words.count, spoken, covered, meeting.duration,
            covered / max(meeting.duration, 1) * 100
        ))
        print("--- \(meeting.speakers.count) speakers, \(meeting.utterances.count) turns ---")
        print(TranscriptExporter.markdown(for: meeting))
    }
}
