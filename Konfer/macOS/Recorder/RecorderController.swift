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

    var microphoneID: String? {
        didSet { if microphoneID != oldValue { previewChoices() } }
    }

    /// Whether the microphone is recorded at all. The chosen device is kept
    /// either way, so switching the microphone off and on again does not lose
    /// it — and so `refreshDevices()` never has to guess what a nil id means.
    var recordsMicrophone = true {
        didSet { if recordsMicrophone != oldValue { previewChoices() } }
    }

    var systemAudio: SystemAudioSource = .none {
        didSet { if systemAudio != oldValue { previewChoices() } }
    }
    var destinationFolder: URL
    var filename: String = RecorderController.defaultFilename()

    private(set) var microphones: [AudioInputDevices.Device] = []
    private(set) var applications: [AudioApplication] = []

    // MARK: - State

    private(set) var state: State = .idle
    private(set) var error: RecordingError?

    /// Peak level per channel, 0...1, for the meters — live from the moment
    /// the window opens, not only once recording has started.
    private(set) var microphoneLevel: Float = 0
    private(set) var systemLevel: Float = 0

    private(set) var fileSize: Int64 = 0

    /// Set when the other side was asked for but has produced nothing but
    /// digital silence for long enough that it is almost certainly not working.
    /// Discovering that after an hour-long call is the worst outcome this
    /// window has, so it is called out while there is still time to restart.
    private(set) var systemAudioSeemsSilent = false

    /// Set once the microphone is audibly picking up the call as well.
    ///
    /// Measured rather than assumed — see ``BleedSuppression`` — and latched:
    /// the recording already contains the bleed by the time this is true, and a
    /// banner that came and went with the conversation would be noise. Worth
    /// saying while the recording is still going, because headphones fix it and
    /// nothing else fixes it as well.
    private(set) var microphoneHearsTheCall = false

    /// Set when a recording finishes, so the window can offer to transcribe it.
    private(set) var finishedRecording: URL?

    // MARK: - Private

    @ObservationIgnored private let applicationsMonitor = AudioApplicationsMonitor()
    @ObservationIgnored private var source: (any RecordingSource)?
    @ObservationIgnored private var writer: TwoChannelWriter?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    /// What feeds the meters while nothing is being recorded. See
    /// ``previewChoices()``.
    @ObservationIgnored private var previewSource: (any RecordingSource)?
    @ObservationIgnored private var previewProbe: LevelProbe?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var isPreviewing = false
    @ObservationIgnored private var outputURL: URL?
    @ObservationIgnored private var systemEverHadSignal = false

    /// Meter samples kept for the bleed measurement, oldest first.
    @ObservationIgnored private var microphoneHistory: [Float] = []
    @ObservationIgnored private var systemHistory: [Float] = []

    /// Meter ticks the measurement runs over. At 80 ms a tick, 150 is twelve
    /// seconds — long enough to hold several of the far end's sentences, which
    /// is what the measurement needs, and short enough to notice inside the
    /// first minute of a call.
    private static let bleedWindow = 150

    init(destinationFolder: URL) {
        self.destinationFolder = destinationFolder
    }

    // MARK: - Devices

    /// Keeps the lists in step with the machine for as long as the window is open.
    ///
    /// Changes are ignored while recording: the lists exist to choose a source,
    /// and re-deriving them mid-recording could move the selection out from
    /// under a tap that is already running.
    ///
    /// The meters run for as long, too: they are there to be checked before
    /// committing to an hour, so they have to move before Record is pressed.
    func startWatchingDevices() {
        refreshDevices()
        applicationsMonitor.start { [weak self] in
            guard let self, state == .idle else { return }
            refreshDevices()
        }
        isPreviewing = true
        previewChoices()
        startMetering()
    }

    func stopWatchingDevices() {
        applicationsMonitor.stop()
        // The meter task is left running: it also watches a recording that
        // outlives the window for silence, and costs nothing once idle.
        isPreviewing = false
        previewChoices()
    }

    func refreshDevices() {
        let attached = AudioInputDevices.available()
        if microphones != attached { microphones = attached }

        var playing = AudioApplications.playingAudio()

        // A call that goes quiet for a moment drops out of "playing audio", but
        // it is still there and still tappable: a tap targets the process
        // object, which outlives the silence. Keeping the chosen app in the
        // list is what lets the picker go on showing it — a selection with no
        // matching tag renders blank — and stops the fallback below from
        // firing on a pause between sentences.
        if case .app(let chosen) = systemAudio,
           !playing.contains(where: { $0.id == chosen.id }),
           AudioApplications.processObjectID(for: chosen.id) != nil {
            playing.append(chosen)
            playing.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // Assigned only when it actually differs: observation has no equality
        // check of its own, so publishing the same list every two seconds
        // would redraw the window for nothing.
        if applications != playing { applications = playing }

        if microphoneID == nil || !microphones.contains(where: { $0.id == microphoneID }) {
            microphoneID = microphones.first?.id
        }
        // A Mac with no input device attached has no microphone to switch on.
        // Said out loud rather than left implied: the picker shows "Off" for a
        // nil device either way, and this stops it saying so while the
        // recorder still expects the microphone to arrive.
        if microphones.isEmpty { recordsMicrophone = false }
        // Only once the process itself is gone — quitting the app being
        // recorded is the one case where the choice genuinely cannot stand.
        // Falling back on silence alone would move the recording to
        // "everything the Mac plays", which needs the full screen-recording
        // permission rather than the narrower one a tap asks for.
        if case .app(let chosen) = systemAudio,
           !applications.contains(where: { $0.id == chosen.id }) {
            systemAudio = applications.isEmpty ? .none : .everything
        }
    }

    // MARK: - Recording

    /// Nothing selected on either side. Recording this would produce a file of
    /// silence, so the button is disabled and `start()` refuses.
    var hasNothingToRecord: Bool {
        !recordsMicrophone && systemAudio == .none
    }

    func start() async {
        guard state == .idle else { return }
        guard !hasNothingToRecord else {
            error = .nothingToRecord
            return
        }
        error = nil
        finishedRecording = nil
        systemAudioSeemsSilent = false
        systemEverHadSignal = false
        microphoneHearsTheCall = false
        microphoneHistory = []
        systemHistory = []
        state = .preparing

        // The preview holds the same devices, and a second tap on the same
        // app is not something to find out about mid-meeting.
        await stopPreview()

        let url = destinationFolder.appendingPathComponent(sanitisedFilename)
        let source = makeSource()

        do {
            let writer = try TwoChannelWriter(url: url)
            if systemAudio == .none { writer.markSilent(.system) }
            if !recordsMicrophone { writer.markSilent(.microphone) }

            try await source.prepare(configuration)
            try await source.start(writingTo: writer)

            self.source = source
            self.writer = writer
            self.outputURL = url
            state = .recording(startedAt: Date())
        } catch let recordingError as RecordingError {
            error = recordingError
            state = .idle
            try? FileManager.default.removeItem(at: url)
            previewChoices()
        } catch {
            self.error = .writeFailed(underlying: error)
            state = .idle
            try? FileManager.default.removeItem(at: url)
            previewChoices()
        }
    }

    func stop() async {
        guard state.isRecording else { return }

        await source?.stop()
        writer?.finish()

        source = nil
        writer = nil
        state = .idle
        previewChoices()

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

    private var configuration: RecordingConfiguration {
        RecordingConfiguration(
            microphoneID: microphoneID,
            recordsMicrophone: recordsMicrophone,
            systemAudio: systemAudio
        )
    }

    private func makeSource() -> any RecordingSource {
        switch systemAudio {
        case .app: AggregateDeviceRecorder()
        case .everything: ScreenCaptureRecorder()
        case .none: MicrophoneOnlyRecorder()
        }
    }

    // MARK: - Preview

    /// Points the meters at whatever is currently chosen, while not recording.
    ///
    /// The same ``RecordingSource`` the recording would use, delivering into a
    /// ``LevelProbe`` instead of a file — a microphone opened on the side
    /// could not show a tap macOS has quietly refused, which is the failure
    /// most worth catching early. It also means the permissions are asked for
    /// when a source is chosen rather than when Record is pressed.
    ///
    /// Each call queues behind the last, which tears its source down first, so
    /// flicking through the pickers never leaves two taps on one app. A source
    /// that can't start — an app that has stopped playing, a refused
    /// permission — leaves its bar flat; the error is Record's to report.
    private func previewChoices() {
        let previous = previewTask
        previous?.cancel()
        previewTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await tearDownPreview()
            guard !Task.isCancelled, isPreviewing, state == .idle, !hasNothingToRecord else {
                return
            }
            let source = makeSource()
            let probe = LevelProbe()
            do {
                try await source.prepare(configuration)
                try await source.start(writingTo: probe)
            } catch {
                await source.stop()
                return
            }
            previewSource = source
            previewProbe = probe
        }
    }

    private func stopPreview() async {
        let wasPreviewing = isPreviewing
        isPreviewing = false
        previewChoices()
        await previewTask?.value
        isPreviewing = wasPreviewing
    }

    private func tearDownPreview() async {
        let source = previewSource
        previewSource = nil
        previewProbe = nil
        await source?.stop()
    }

    // MARK: - Metering

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self else { return }
                let sink: (any AudioSink)? = writer ?? previewProbe
                let levels = sink?.consumeLevels() ?? (microphone: 0, system: 0)
                // Fall towards silence rather than snapping, so a meter reads
                // as a level rather than a flicker.
                self.microphoneLevel = max(levels.microphone, self.microphoneLevel * 0.6)
                self.systemLevel = max(levels.system, self.systemLevel * 0.6)

                guard self.state.isRecording else { continue }
                if levels.system > 0 { self.systemEverHadSignal = true }
                self.watchForBleed(levels)
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

    /// Watches for the call arriving on the microphone as well as on its own
    /// channel.
    ///
    /// Runs on the meter's own samples rather than a second read of the audio:
    /// a peak squared is an energy proxy, and energy per frame is exactly what
    /// ``BleedSuppression`` measures. The frames are 80 ms rather than the
    /// 20 ms used on a finished recording, which loses the lag — it comes out
    /// as zero — and keeps the only thing being asked here, which is whether
    /// the microphone rises and falls with the call.
    private func watchForBleed(_ levels: (microphone: Float, system: Float)) {
        guard !microphoneHearsTheCall, recordsMicrophone, systemAudio != .none else { return }

        microphoneHistory.append(levels.microphone * levels.microphone)
        systemHistory.append(levels.system * levels.system)
        if microphoneHistory.count > Self.bleedWindow {
            microphoneHistory.removeFirst()
            systemHistory.removeFirst()
        }
        guard microphoneHistory.count == Self.bleedWindow else { return }

        microphoneHearsTheCall = BleedSuppression.coupling(
            microphone: microphoneHistory,
            system: systemHistory
        ) != nil
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
