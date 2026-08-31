//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// Drives the recorder window: what to capture, and the state of capturing it.
@Observable @MainActor
final class RecorderController {

    enum State: Equatable {
        case idle
        case preparing
        case recording(startedAt: Date)

        var isRecording: Bool {
            if case .recording = self { return true }
            return false
        }

        /// True while the controls should be locked — changing the microphone
        /// halfway through a recording has no sensible meaning.
        var isBusy: Bool { self != .idle }
    }

    // MARK: - Choices

    var microphoneID: String?
    var systemAudio: SystemAudioSource = .none
    var destinationFolder: URL
    var filename: String = RecorderController.defaultFilename()

    private(set) var microphones: [AudioInputDevices.Device] = []
    private(set) var applications: [AudioApplication] = []

    // MARK: - State

    private(set) var state: State = .idle
    private(set) var error: RecordingError?

    /// Peak level per channel, 0...1, for the meters.
    private(set) var microphoneLevel: Float = 0
    private(set) var systemLevel: Float = 0

    private(set) var fileSize: Int64 = 0

    /// Set when the other side was asked for but has produced nothing but
    /// digital silence for long enough that it is almost certainly not working.
    /// Discovering that after an hour-long call is the worst outcome this
    /// window has, so it is called out while there is still time to restart.
    private(set) var systemAudioSeemsSilent = false

    /// Set when a recording finishes, so the window can offer to transcribe it.
    private(set) var finishedRecording: URL?

    // MARK: - Private

    @ObservationIgnored private var source: (any RecordingSource)?
    @ObservationIgnored private var writer: TwoChannelWriter?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var systemEverHadSignal = false

    init(destinationFolder: URL) {
        self.destinationFolder = destinationFolder
    }

    // MARK: - Devices

    func refreshDevices() {
        microphones = AudioInputDevices.available()
        applications = AudioApplications.playingAudio()

        if microphoneID == nil || !microphones.contains(where: { $0.id == microphoneID }) {
            microphoneID = microphones.first?.id
        }
        // An app that stopped playing can't be tapped any more.
        if case .app(let chosen) = systemAudio,
           !applications.contains(where: { $0.id == chosen.id }) {
            systemAudio = applications.isEmpty ? .none : .everything
        }
    }

    // MARK: - Recording

    func start() async {
        guard state == .idle else { return }
        error = nil
        finishedRecording = nil
        systemAudioSeemsSilent = false
        systemEverHadSignal = false
        state = .preparing

        let url = destinationFolder.appendingPathComponent(sanitisedFilename)
        let configuration = RecordingConfiguration(
            microphoneID: microphoneID,
            systemAudio: systemAudio,
            outputURL: url
        )

        let source: any RecordingSource = switch systemAudio {
        case .app: AggregateDeviceRecorder()
        case .everything: ScreenCaptureRecorder()
        case .none: MicrophoneOnlyRecorder()
        }

        do {
            let writer = try TwoChannelWriter(url: url)
            if systemAudio == .none { writer.markSilent(.system) }

            try await source.prepare(configuration)
            try await source.start(writingTo: writer)

            self.source = source
            self.writer = writer
            self.outputURL = url
            state = .recording(startedAt: Date())
            startMetering()
        } catch let recordingError as RecordingError {
            error = recordingError
            state = .idle
            try? FileManager.default.removeItem(at: url)
        } catch {
            self.error = .writeFailed(underlying: error)
            state = .idle
            try? FileManager.default.removeItem(at: url)
        }
    }

    func stop() async {
        guard state.isRecording else { return }
        meterTask?.cancel()
        meterTask = nil

        await source?.stop()
        writer?.finish()

        source = nil
        writer = nil
        state = .idle
        microphoneLevel = 0
        systemLevel = 0

        finishedRecording = outputURL
        // Ready for the next one.
        filename = Self.defaultFilename()
    }

    func acknowledgeFinishedRecording() {
        finishedRecording = nil
        outputURL = nil
    }

    func dismissError() {
        error = nil
    }

    // MARK: - Metering

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, let writer = self.writer else { return }
                let levels = writer.consumeLevels()
                // Fall towards silence rather than snapping, so a meter reads
                // as a level rather than a flicker.
                self.microphoneLevel = max(levels.microphone, self.microphoneLevel * 0.6)
                self.systemLevel = max(levels.system, self.systemLevel * 0.6)

                if levels.system > 0 { self.systemEverHadSignal = true }
                if case .recording(let startedAt) = self.state,
                   self.systemAudio != .none,
                   !self.systemEverHadSignal,
                   Date().timeIntervalSince(startedAt) > 4 {
                    self.systemAudioSeemsSilent = true
                }
                if let url = self.outputURL,
                   let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attributes[.size] as? Int64 {
                    self.fileSize = size
                }
            }
        }
    }

    // MARK: - Naming

    private var sanitisedFilename: String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? Self.defaultFilename() : trimmed
        let named = base.replacingOccurrences(of: "/", with: "-")
        return named.hasSuffix(".m4a") ? named : named + ".m4a"
    }

    private static func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return "Recording \(formatter.string(from: Date())).m4a"
    }
}
