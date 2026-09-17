//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI

/// Set up a recording, watch it happen, stop it.
struct RecorderView: View {

    @Environment(TranscriptionPipeline.self) private var pipeline
    @Environment(AppSettings.self) private var appSettings

    @State private var controller = RecorderController(
        destinationFolder: RecorderView.fallbackFolder
    )
    @State private var isChoosingFolder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settings
            Divider()
            meters
            Divider()
            controls
        }
        .frame(width: 460)
        .task {
            controller.startWatchingDevices()
            controller.destinationFolder = Self.storedFolder(appSettings.recordingFolder)
        }
        .onDisappear { controller.stopWatchingDevices() }
        .fileImporter(
            isPresented: $isChoosingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                controller.destinationFolder = url
                appSettings.recordingFolder = url.path
            }
        }
        .sheet(item: Binding(
            get: { controller.finishedRecording.map(FinishedRecording.init) },
            set: { if $0 == nil { controller.acknowledgeFinishedRecording() } }
        )) { finished in
            ImportSheet(
                url: finished.url,
                // Konfer wrote this file, so the two channels are known to be
                // the microphone and system audio rather than a stereo image.
                // Nothing else can tell the pipeline that — and it is also what
                // makes the speakers question worth asking.
                separatesSources: true
            ) { language, speakers, trim, suppressBleed in
                pipeline.enqueue(
                    finished.url,
                    language: language,
                    expectedSpeakers: speakers,
                    trim: trim,
                    separatesSources: true,
                    suppressesBleed: suppressBleed
                )
            }
        }
    }

    // MARK: - Settings

    private var settings: some View {
        Form {
            Section {
                LabeledContent("Save to") {
                    HStack(spacing: 6) {
                        Text(controller.destinationFolder.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") { isChoosingFolder = true }
                            .controlSize(.small)
                    }
                }
                TextField("Name", text: $controller.filename)

                Picker("Microphone", selection: microphoneBinding) {
                    ForEach(controller.microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                    Divider()
                    Text("Off — the other side only").tag(String?.none)
                }

                Picker("Also record", selection: systemAudioBinding) {
                    Text("Nothing — microphone only").tag(SystemAudioSource.none)
                    ForEach(controller.applications) { app in
                        Text(app.name).tag(SystemAudioSource.app(app))
                    }
                    Text("Everything the Mac plays").tag(SystemAudioSource.everything)
                }

                Text(systemAudioExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text(channelExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(controller.state.isBusy)
    }

    /// Why the other side is silent, most likely cause first.
    ///
    /// A refused system-audio permission is the one failure that looks exactly
    /// like a quiet call: macOS returns success from every call and hands the
    /// tap nothing but zeros, so this banner is the only place the user can
    /// learn that a permission is involved at all.
    private var silenceExplanation: String {
        switch controller.systemAudio {
        case .app(let app):
            "The right channel has been silent since recording started. macOS "
            + "may have refused permission to record system audio, which it does "
            + "without saying so — check Privacy & Security ▸ Screen & System "
            + "Audio Recording. Otherwise, make sure \(app.name) is actually "
            + "playing the call."
        default:
            "The right channel has been silent since recording started. Check "
            + "that the call is actually playing, and that Konfer is allowed to "
            + "record in Privacy & Security ▸ Screen & System Audio Recording."
        }
    }

    private var systemAudioBinding: Binding<SystemAudioSource> {
        Binding(
            get: { controller.systemAudio },
            set: { controller.systemAudio = $0 }
        )
    }

    /// The microphone picker's selection, where nil is "Off".
    ///
    /// Off is a flag of its own rather than a nil device id: `refreshDevices()`
    /// reassigns a nil id to the first attached microphone every couple of
    /// seconds, so a picker where nil meant off would switch itself back on
    /// while the user was still setting up. The chosen device is also kept
    /// while off, so turning the microphone back on returns to it.
    private var microphoneBinding: Binding<String?> {
        Binding(
            get: { controller.recordsMicrophone ? controller.microphoneID : nil },
            set: { selection in
                controller.recordsMicrophone = selection != nil
                if let selection { controller.microphoneID = selection }
            }
        )
    }

    private var systemAudioExplanation: String {
        guard !controller.hasNothingToRecord else {
            return "With the microphone off and nothing else chosen, there is "
                + "nothing to record."
        }
        return switch controller.systemAudio {
        case .none:
            "Only you will be recorded."
        case .app(let app):
            controller.recordsMicrophone
            ? "Only \(app.name) is recorded, so notifications and music stay out. "
              + "macOS asks to allow system-audio recording the first time."
            : "Only \(app.name) is recorded — not you, and not notifications or "
              + "music. macOS asks to allow system-audio recording the first time."
        case .everything:
            controller.recordsMicrophone
            ? "Records every sound the Mac makes, including notifications. macOS "
              + "asks for the full screen-recording permission the first time."
            : "Records every sound the Mac makes, including notifications, but not "
              + "you — so macOS asks only about the screen, never the microphone."
        }
    }

    /// What the two channels will hold. Worth saying, because a recording with
    /// the microphone off is a file whose left channel is deliberately silent.
    private var channelExplanation: String {
        controller.recordsMicrophone
        ? "Your microphone is recorded on the left channel and the other side on "
          + "the right, so the two can be told apart later. About 350 MB an hour."
        : "The other side is recorded on the right channel and the left stays "
          + "silent, so every voice in the transcript will be marked as being on "
          + "the call. About 350 MB an hour."
    }

    // MARK: - Meters

    private var meters: some View {
        VStack(spacing: 8) {
            LevelMeter(
                label: "Microphone",
                level: controller.microphoneLevel,
                color: .blue,
                isActive: controller.recordsMicrophone
            )
            LevelMeter(
                label: "Other side",
                level: controller.systemLevel,
                color: .orange,
                isActive: controller.systemAudio != .none
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = controller.error {
                errorBanner(error)
            }

            if controller.systemAudioSeemsSilent {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing is coming from the other side")
                            .font(.callout)
                        Text(silenceExplanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let url = PrivacySettings.screenAndSystemAudio {
                            Button("Open Privacy Settings…") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if controller.microphoneHearsTheCall {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "headphones")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The microphone is picking up the call")
                            .font(.callout)
                        Text(
                            "Headphones would keep the two sides apart. Without "
                            + "them, the people on the call can end up listed as "
                            + "being in the room — say the call came out of the "
                            + "speakers when you transcribe this, and Konfer will "
                            + "ignore the microphone where only the call is audible."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button {
                    Task {
                        if controller.state.isRecording {
                            await controller.stop()
                        } else {
                            await controller.start()
                        }
                    }
                } label: {
                    Label(
                        controller.state.isRecording ? "Stop" : "Record",
                        systemImage: controller.state.isRecording ? "stop.fill" : "record.circle"
                    )
                    .frame(width: 80)
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(controller.state == .preparing || controller.hasNothingToRecord)
                .tint(controller.state.isRecording ? .red : .accentColor)
                .buttonStyle(.borderedProminent)

                Spacer()

                if case .recording(let startedAt) = controller.state {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(.title3, design: .rounded))
                        .monospacedDigit()
                    if controller.fileSize > 0 {
                        Text(ModelStorage.formattedSize(controller.fileSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if controller.state == .preparing {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(20)
    }

    private func errorBanner(_ error: RecordingError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "Recording failed.")
                    .font(.callout)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Naming the pane isn't much help once the prompt is spent —
                // see `privacySettingsURL`.
                if let settings = error.privacySettingsURL {
                    Button("Open Privacy Settings…") {
                        NSWorkspace.shared.open(settings)
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            Spacer()
            Button("Dismiss") { controller.dismissError() }
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension RecorderView {

    /// Downloads: where recordings-in-progress naturally live before they are
    /// filed anywhere, and where the rest of this app's audio already comes
    /// from.
    static var fallbackFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// The remembered folder, if it is still a folder that exists.
    static func storedFolder(_ path: String) -> URL {
        guard !path.isEmpty else { return fallbackFolder }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return fallbackFolder }
        return URL(fileURLWithPath: path)
    }
}

/// Wraps the finished file so it can drive a `sheet(item:)`.
private struct FinishedRecording: Identifiable {
    let url: URL
    var id: String { url.path }
    init(_ url: URL) { self.url = url }
}
