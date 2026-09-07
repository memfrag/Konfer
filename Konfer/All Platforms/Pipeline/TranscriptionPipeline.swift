//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import FluidAudio
import Observation

/// Runs recordings through diarization and speech recognition, one at a time.
///
/// Both stages saturate the Neural Engine, so running them concurrently buys
/// nothing and makes progress meaningless. They run in sequence, diarization
/// first, so speaker information is ready before the longer stage finishes.
///
/// Only one recording is processed at a time; further imports queue behind it.
/// Nothing partial is ever persisted, so there is no resume state to version.
///
@Observable @MainActor
final class TranscriptionPipeline {

    // MARK: - Types

    struct Job: Identifiable, Sendable {
        let id = UUID()
        let sourceURL: URL
        let title: String
        let language: MeetingLanguage
        let expectedSpeakers: Int?
        /// Follows from `language`, unless overridden for benchmarking.
        let backend: ASRBackendKind
        let fastTranscription: Bool

        /// The stretch to transcribe, or nil for the whole recording.
        let trim: KeptRange?

        /// The meeting this run replaces, when it is a re-run rather than an
        /// import. A failed or garbled transcript is worth another attempt on a
        /// narrower range, and it should land back on the same row in the
        /// sidebar rather than beside it.
        let replacing: UUID?
    }

    enum Stage: Equatable {
        case idle
        /// First run only: several hundred megabytes of models from Hugging Face.
        case preparingModels(Double)
        case diarizing(Double)
        case transcribing(Double)

        var isRunning: Bool { self != .idle }

        var label: String {
            switch self {
            case .idle: "Idle"
            case .preparingModels: "Downloading speech models"
            case .diarizing: "Identifying speakers"
            case .transcribing: "Transcribing"
            }
        }

        /// Fraction in [0, 1], or `nil` while a stage can't report progress.
        var fraction: Double? {
            switch self {
            case .idle: nil
            case .preparingModels(let value), .diarizing(let value), .transcribing(let value):
                value
            }
        }
    }

    // MARK: - Observable state

    private(set) var stage: Stage = .idle
    private(set) var activeJob: Job?

    /// When the active job started, for the elapsed clock.
    private(set) var activeJobStartedAt: Date?
    private(set) var queue: [Job] = []
    private(set) var lastError: PipelineError?

    /// The meeting produced by the most recent successful run, so the UI can
    /// select it automatically.
    private(set) var lastFinishedMeetingID: UUID?

    var isRunning: Bool { activeJob != nil }

    // MARK: - Dependencies

    @ObservationIgnored private let registry: BackendRegistry
    @ObservationIgnored private let diarizer: DiarizationService
    @ObservationIgnored private let meetingStore: MeetingStore
    @ObservationIgnored private let speakerStore: SpeakerStore
    @ObservationIgnored private var runTask: Task<Void, Never>?

    /// Forces one model regardless of language, for comparing models on the
    /// same recording. Unset in normal use, where the language decides.
    ///
    /// `KONFER_BACKEND=apple-speech|kb-whisper-small|kb-whisper-large`
    @ObservationIgnored
    static let backendOverride: ASRBackendKind? = ProcessInfo.processInfo
        .environment["KONFER_BACKEND"]
        .flatMap(ASRBackendKind.init(rawValue:))

    /// Whether new jobs trade completeness for speed. Read from settings.
    var fastTranscription = false

    init(
        registry: BackendRegistry = BackendRegistry(),
        diarizer: DiarizationService,
        meetingStore: MeetingStore,
        speakerStore: SpeakerStore
    ) {
        self.registry = registry
        self.diarizer = diarizer
        self.meetingStore = meetingStore
        self.speakerStore = speakerStore
    }

    // MARK: - Queue

    func enqueue(
        _ url: URL,
        language: MeetingLanguage,
        expectedSpeakers: Int? = nil,
        trim: KeptRange? = nil,
        replacing: UUID? = nil,
        title: String? = nil
    ) {
        let job = Job(
            sourceURL: url,
            title: title ?? url.deletingPathExtension().lastPathComponent,
            language: language,
            expectedSpeakers: expectedSpeakers,
            backend: Self.backendOverride ?? ASRBackendKind(transcribing: language),
            fastTranscription: fastTranscription,
            trim: trim,
            replacing: replacing
        )
        queue.append(job)
        startNextIfIdle()
    }

    /// Abandons the running job. Nothing partial is kept.
    func cancelActive() {
        runTask?.cancel()
    }

    func clearError() {
        lastError = nil
    }

    /// Discards every model in memory, so the files on disk can be deleted.
    func unloadModels() async {
        await registry.unloadAll()
        await diarizer.unload()
    }

    private func startNextIfIdle() {
        guard activeJob == nil, !queue.isEmpty else { return }
        let job = queue.removeFirst()
        activeJob = job
        activeJobStartedAt = Date()
        lastError = nil

        runTask = Task { [weak self] in
            await self?.run(job)
            self?.finish()
        }
    }

    private func finish() {
        activeJob = nil
        activeJobStartedAt = nil
        stage = .idle
        runTask = nil
        startNextIfIdle()
    }

    // MARK: - The run

    private func run(_ job: Job) async {

        var prepared: PreparedAudio?
        defer { prepared?.cleanUp() }

        do {
            // 0. Two things have to hold before any work starts, because
            //    diarization takes a minute on a long recording and failing
            //    after it would waste all of it.

            //    The chosen model has to be able to speak the chosen language.
            guard job.backend.supports(job.language) else {
                throw PipelineError.languageUnsupported(job.language)
            }

            //    And its model has to be on disk already. The UI stops this
            //    first — see `ImportSheet` — so reaching here means another
            //    caller slipped past. `KONFER_BACKEND` is exempt: benchmarking
            //    keeps the old lazy download.
            if Self.backendOverride == nil,
               let required = ManagedModel(transcribing: job.language),
               !required.isInstalled {
                throw PipelineError.modelNotDownloaded(required)
            }

            // 1. Normalize the input. Video files get their audio extracted to a
            //    temporary file; audio files pass straight through.
            let audio = try await AudioSourcePreparer.prepare(
                job.sourceURL,
                trimmedTo: job.trim
            )
            prepared = audio
            try checkCancellation()

            // 2. Diarization: models, then the pass itself. A failure here is
            //    survivable — see the degraded path below.
            var segments: [TimedSpeakerSegment] = []
            var degraded: DegradedStage?

            do {
                if await !diarizer.isPrepared { stage = .preparingModels(0) }
                try await diarizer.prepare { [weak self] fraction in
                    Task { @MainActor in self?.stage = .preparingModels(fraction) }
                }
                try checkCancellation()

                stage = .diarizing(0)
                segments = try await diarizer.diarize(
                    audio.url,
                    expectedSpeakers: job.expectedSpeakers
                ) { [weak self] fraction in
                    Task { @MainActor in self?.stage = .diarizing(fraction) }
                }
                if segments.isEmpty { degraded = .diarization }
            } catch is CancellationError {
                throw PipelineError.cancelled
            } catch {
                // No speakers is not a reason to throw away a transcript.
                segments = []
                degraded = .diarization
            }
            try checkCancellation()

            // 3. Speech recognition. This one is load-bearing: speaker segments
            //    with no words have no use, so a failure fails the run.
            let backend = await registry.backend(for: job.backend)
            if await !backend.isPrepared(for: job.language) { stage = .preparingModels(0) }
            do {
                try await backend.prepare(for: job.language) { [weak self] fraction in
                    Task { @MainActor in self?.stage = .preparingModels(fraction) }
                }
            } catch is CancellationError {
                throw PipelineError.cancelled
            } catch {
                throw PipelineError.modelDownloadFailed(underlying: error)
            }
            try checkCancellation()

            stage = .transcribing(0)
            let transcribed: TranscribedAudio
            do {
                let request = TranscriptionRequest(
                    url: audio.url,
                    language: job.language,
                    speechRegions: SpeechRegion.regions(
                        from: segments,
                        padding: SpeechRegion.padding
                    ),
                    allowsChunking: job.fastTranscription
                )
                transcribed = try await backend.transcribe(request) { [weak self] fraction in
                    Task { @MainActor in self?.stage = .transcribing(fraction) }
                }
            } catch is CancellationError {
                throw PipelineError.cancelled
            } catch {
                throw PipelineError.transcriptionFailed(underlying: error)
            }
            try checkCancellation()

            // 4. The merge, and the meeting it produces.
            //
            //    Every stage above read the prepared file, so its timestamps
            //    start at zero even when that file is an extract from the
            //    middle of the recording. They are put back here, once, so
            //    that nothing downstream — playback, waveform, export — has to
            //    know a trim happened.
            let utterances = Self.shifting(
                SpeakerAligner.align(words: transcribed.words, segments: segments),
                by: audio.startOffset
            )
            let speakers = makeSpeakerLabels(segments: segments, utterances: utterances)
            let cuts = transcribed.sliceCuts.map { $0 + audio.startOffset }

            if let replacing = job.replacing, var existing = meetingStore.meeting(replacing) {
                // A re-run replaces the transcript and nothing else: the title,
                // the place in the library and the trim that prompted the re-run
                // are all still the user's.
                existing.speakers = speakerStore.annotate(speakers)
                existing.utterances = utterances
                existing.degraded = degraded
                existing.sliceCuts = cuts.isEmpty ? nil : cuts
                existing.wasFastTranscribed = job.fastTranscription ? true : nil
                existing.duration = audio.sourceDuration

                // The language the re-run was told to use, which may not be
                // the one the first run used. Without this a meeting
                // transcribed again in another language keeps the old label,
                // and everything downstream that reads it — the routing
                // table, the translate sheet's source — believes it.
                existing.language = job.language

                // Every turn above is a new `Utterance` with a new id, so a
                // translation keyed by the old ones describes nothing at all.
                existing.removeTranslation()
                meetingStore.update(existing)
                lastFinishedMeetingID = existing.id
            } else {
                let meeting = Meeting(
                    id: UUID(),
                    title: job.title,
                    audioPath: job.sourceURL.path,
                    // The recording's own length, not the extract's: the
                    // library points at the whole file whatever was read.
                    duration: audio.sourceDuration,
                    importedAt: Date(),
                    language: job.language,
                    speakers: speakerStore.annotate(speakers),
                    utterances: utterances,
                    degraded: degraded,
                    sliceCuts: cuts.isEmpty ? nil : cuts,
                    // Left nil on a trimmed import: nothing was transcribed
                    // outside the range, so there is nothing to collapse.
                    keptRange: nil,
                    wasFastTranscribed: job.fastTranscription ? true : nil
                )
                meetingStore.add(meeting)
                lastFinishedMeetingID = meeting.id
            }

        } catch let error as PipelineError {
            if case .cancelled = error { return }
            lastError = error
        } catch {
            lastError = .transcriptionFailed(underlying: error)
        }
    }

    /// Moves turns from the extract's timeline back onto the recording's.
    ///
    /// Internal so it can be tested directly: it is the whole of what makes a
    /// trimmed transcription line up with the untouched file it came from, and
    /// an off-by-one here is a transcript that plays against the wrong audio.
    static func shifting(
        _ utterances: [Utterance],
        by offset: TimeInterval
    ) -> [Utterance] {
        guard offset != 0 else { return utterances }
        return utterances.map { utterance in
            Utterance(
                id: utterance.id,
                speakerId: utterance.speakerId,
                start: utterance.start + offset,
                end: utterance.end + offset,
                text: utterance.text,
                words: utterance.words?.map {
                    WordSpan(word: $0.word, start: $0.start + offset, end: $0.end + offset)
                },
                isEdited: utterance.isEdited
            )
        }
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw PipelineError.cancelled }
    }

    // MARK: - Speaker roster

    /// Turns raw diarizer cluster ids into the meeting's speaker roster.
    ///
    /// Clusters are numbered by when they first speak, so "Speaker 1" is the
    /// person who opened the meeting rather than whichever id the clusterer
    /// happened to assign first.
    private func makeSpeakerLabels(
        segments: [TimedSpeakerSegment],
        utterances: [Utterance]
    ) -> [SpeakerLabel] {

        var order: [String] = []
        var grouped: [String: [TimedSpeakerSegment]] = [:]

        for segment in segments.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds }) {
            if grouped[segment.speakerId] == nil { order.append(segment.speakerId) }
            grouped[segment.speakerId, default: []].append(segment)
        }

        var labels: [SpeakerLabel] = order.enumerated().map { index, id in
            let clusterSegments = grouped[id] ?? []
            return SpeakerLabel(
                id: id,
                name: "Speaker \(index + 1)",
                embedding: VoiceEmbedding.mean(of: clusterSegments),
                totalDuration: clusterSegments.reduce(0) {
                    $0 + TimeInterval($1.durationSeconds)
                }
            )
        }

        // Words that landed outside every segment, or a run with no segments at
        // all, are attributed to a single unknown speaker.
        if utterances.contains(where: { $0.speakerId == SpeakerLabel.unknownID }),
           !labels.contains(where: { $0.id == SpeakerLabel.unknownID }) {
            labels.append(.unknown)
        }

        return labels
    }
}
