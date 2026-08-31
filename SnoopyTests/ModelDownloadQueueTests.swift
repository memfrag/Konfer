//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Snoopy

/// Which model a language needs Snoopy to have fetched, and what the queue does
/// with that.
///
/// The queue runs against a stubbed fetcher: the ordering and the failure
/// handling are the parts worth testing, and downloading three gigabytes to
/// check them is not an option. The fetching itself belongs to FluidAudio and
/// WhisperKit, and `PipelineIntegrationTests` exercises it against real audio.

/// A fetcher that installs instantly and remembers what it was asked for.
///
/// `nonisolated` because the queue calls it through `@Sendable` closures; the
/// app builds with default-`MainActor` isolation, so a nested type would
/// otherwise inherit it and refuse to be called from them.
private nonisolated final class Stub: @unchecked Sendable {

    var installed: Set<ManagedModel> = []
    var downloaded: [ManagedModel] = []
    var failures: Set<ManagedModel> = []

    /// Holds downloads open, so a test can observe a queue mid-flight.
    var blocked = false

    struct Failure: Error {}

    func fetcher() -> ModelDownloadQueue.Fetcher {
        ModelDownloadQueue.Fetcher(
            isInstalled: { [self] in installed.contains($0) },
            download: { [self] model, progress in
                while blocked, !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1))
                }
                try Task.checkCancellation()
                if failures.contains(model) { throw Failure() }
                progress(1)
                downloaded.append(model)
                installed.insert(model)
            },
            remove: { [self] in installed.remove($0) }
        )
    }
}

@MainActor
struct ModelDownloadQueueTests {

    // MARK: - Fixtures

    /// Runs the queue until it has nothing left to do.
    private func drain(_ queue: ModelDownloadQueue) async {
        while queue.isRunning {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    // MARK: - What a language needs

    @Test(
        "The languages Apple covers need nothing downloaded",
        arguments: [MeetingLanguage.english, .german, .spanish, .french, .italian, .portuguese]
    )
    func appleLanguagesNeedNoModel(_ language: MeetingLanguage) {
        #expect(ManagedModel(transcribing: language) == nil)
    }

    @Test("Swedish needs KB-Whisper Large")
    func swedishNeedsKBWhisper() {
        #expect(ManagedModel(transcribing: .swedish) == .kbWhisperLarge)
    }

    @Test(
        "Danish, Dutch and Polish need stock Whisper",
        arguments: [MeetingLanguage.danish, .dutch, .polish]
    )
    func unservedLanguagesNeedWhisperLargeV3(_ language: MeetingLanguage) {
        #expect(ManagedModel(transcribing: language) == .whisperLargeV3)
    }

    @Test("A model lists exactly the languages that route to it")
    func modelsListTheirLanguages() {
        #expect(ManagedModel.kbWhisperLarge.languages == [.swedish])
        #expect(ManagedModel.whisperLargeV3.languages == [.danish, .dutch, .polish])
        // Every language needs it, so naming any subset would mislead.
        #expect(ManagedModel.diarization.languages.isEmpty)
    }

    // MARK: - Where models land

    @Test("WhisperKit's model folder sits inside Snoopy's own models directory")
    func managedModelLandsInSnoopysDirectory() {
        // Derived from WhisperKit's cache layout rather than assumed. If it
        // ever stops matching, `isInstalled` silently returns false forever and
        // a downloaded model looks missing — so it is worth pinning.
        let folder = WhisperKitModelStore.directory(for: .largeV3)
        #expect(folder.path.hasPrefix(KBWhisperModelStore.directory.path))
        #expect(folder.lastPathComponent == "openai_whisper-large-v3")
    }

    // MARK: - The queue

    @Test("Models download one at a time, in the order they were asked for")
    func downloadsRunOneAtATime() async {
        let stub = Stub()
        stub.blocked = true
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.diarization)
        queue.enqueue(.kbWhisperLarge)
        queue.enqueue(.whisperLargeV3)

        #expect(queue.active == .diarization)
        #expect(queue.pending == [.kbWhisperLarge, .whisperLargeV3])
        #expect(queue.state(of: .kbWhisperLarge) == .queued)

        stub.blocked = false
        await drain(queue)

        #expect(stub.downloaded == [.diarization, .kbWhisperLarge, .whisperLargeV3])
        #expect(queue.state(of: .whisperLargeV3) == .installed)
        #expect(!queue.isRunning)
    }

    @Test("Queueing the same model twice doesn't download it twice")
    func queueingIsIdempotent() async {
        let stub = Stub()
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.kbWhisperLarge)
        queue.enqueue(.kbWhisperLarge)
        await drain(queue)

        #expect(stub.downloaded == [.kbWhisperLarge])
    }

    @Test("An already-installed model is never downloaded again")
    func installedModelsAreSkipped() async {
        let stub = Stub()
        stub.installed = [.kbWhisperLarge]
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.kbWhisperLarge)
        await drain(queue)

        #expect(stub.downloaded.isEmpty)
        #expect(queue.state(of: .kbWhisperLarge) == .installed)
    }

    @Test("A failure is kept on its own row, and the queue carries on")
    func failureDoesNotStopTheQueue() async {
        let stub = Stub()
        stub.failures = [.kbWhisperLarge]
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.kbWhisperLarge)
        queue.enqueue(.whisperLargeV3)
        await drain(queue)

        #expect(queue.state(of: .kbWhisperLarge).isFailed)
        #expect(queue.state(of: .whisperLargeV3) == .installed)
        #expect(stub.downloaded == [.whisperLargeV3])
    }

    @Test("A download that reports success without installing counts as failed")
    func silentlyIncompleteDownloadIsAFailure() async {
        // Reports success but leaves nothing on disk — what an interrupted
        // WhisperKit snapshot looks like from here.
        let queue = ModelDownloadQueue(fetcher: ModelDownloadQueue.Fetcher(
            isInstalled: { _ in false },
            download: { _, progress in progress(1) },
            remove: { _ in }
        ))

        queue.enqueue(.whisperLargeV3)
        await drain(queue)

        #expect(queue.state(of: .whisperLargeV3).isFailed)
    }

    @Test("Stopping clears what hasn't started")
    func cancellingEmptiesTheQueue() async {
        let stub = Stub()
        stub.blocked = true
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.diarization)
        queue.enqueue(.whisperLargeV3)
        queue.cancelAll()
        stub.blocked = false
        await drain(queue)

        #expect(queue.pending.isEmpty)
        #expect(!stub.downloaded.contains(.whisperLargeV3))
    }

    // MARK: - What a set of languages implies

    @Test("Asking for Apple's languages queues only the shared diarization model")
    func appleLanguagesQueueOnlyDiarization() async {
        let stub = Stub()
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueueEverythingNeeded(for: [.english, .german, .french])
        await drain(queue)

        #expect(stub.downloaded == [.diarization])
    }

    @Test("Asking for Polish queues stock Whisper alongside diarization")
    func polishQueuesWhisper() async {
        let stub = Stub()
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueueEverythingNeeded(for: [.english, .polish])
        await drain(queue)

        #expect(stub.downloaded == [.diarization, .whisperLargeV3])
    }

    @Test("What's left to download covers the running model and the waiting ones")
    func remainingBytesCoversActiveAndPending() {
        let stub = Stub()
        stub.blocked = true
        let queue = ModelDownloadQueue(fetcher: stub.fetcher())

        queue.enqueue(.kbWhisperLarge)
        queue.enqueue(.whisperLargeV3)

        #expect(queue.remainingBytes
                == ManagedModel.kbWhisperLarge.estimatedBytes
                + ManagedModel.whisperLargeV3.estimatedBytes)
        queue.cancelAll()
    }
}

// MARK: - Helpers

private extension ModelDownloadQueue.State {
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
