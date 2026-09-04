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
            controller.refreshDevices()
            controller.destinationFolder = Self.storedFolder(appSettings.recordingFolder)
        }
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
            ImportSheet(url: finished.url, alreadyTranscribed: nil) { language, speakers in
                pipeline.enqueue(finished.url, language: language, expectedSpeakers: speakers)
            } onOpenExisting: { _ in }
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

                Picker("Microphone", selection: $controller.microphoneID) {
                    ForEach(controller.microphones) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
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
                Text(
                    "Your microphone is recorded on the left channel and the other "
                    + "side on the right, so the two can be told apart later. "
                    + "About 350 MB an hour."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(controller.state.isBusy)
    }

    private var systemAudioBinding: Binding<SystemAudioSource> {
        Binding(
            get: { controller.systemAudio },
            set: { controller.systemAudio = $0 }
        )
    }

    private var systemAudioExplanation: String {
        switch controller.systemAudio {
        case .none:
            "Only you will be recorded."
        case .app(let app):
            "Only \(app.name) is recorded, so notifications and music stay out. "
            + "No screen-recording permission needed."
        case .everything:
            "Records every sound the Mac makes, including notifications. macOS "
            + "asks for screen-recording permission the first time."
        }
    }

    // MARK: - Meters

    private var meters: some View {
        VStack(spacing: 8) {
            LevelMeter(
                label: "Microphone",
                level: controller.microphoneLevel,
                color: .blue
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
                        Text(
                            "The right channel has been silent since recording "
                            + "started. Check that the call is actually playing, "
                            + "or stop and choose \"Everything the Mac plays\"."
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
                .disabled(controller.state == .preparing)
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
