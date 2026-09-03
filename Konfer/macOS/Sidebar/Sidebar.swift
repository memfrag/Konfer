//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct Sidebar: View {

    @Environment(\.openWindow) private var openWindow
    @Environment(MeetingStore.self) private var meetingStore
    @Environment(TranscriptionPipeline.self) private var pipeline

    @State private var searchText: String = ""
    @State private var selection: SidebarSelection?

    /// What the file panel is open for, if it is open.
    @State private var importing: ImportKind?

    /// The file waiting on its confirmation sheet.
    @State private var pending: PendingImport?

    /// A transcript file that turned out not to be one.
    @State private var importError: TranscriptImportError?

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detail
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            offerImport(of: url)
            return true
        }
        .fileImporter(
            isPresented: Binding(
                get: { importing != nil },
                set: { if !$0 { importing = nil } }
            ),
            allowedContentTypes: (importing ?? .recording).contentTypes,
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                offerImport(of: url)
            }
        }
        .sheet(item: $pending) { pending in
            switch pending {
            case .recording(let url, let alreadyTranscribed):
                ImportSheet(url: url, alreadyTranscribed: alreadyTranscribed) { language, speakers in
                    pipeline.enqueue(url, language: language, expectedSpeakers: speakers)
                } onOpenExisting: { meeting in
                    selection = .meeting(meeting.id)
                }
            case .transcript(let url, let transcript):
                TranscriptImportSheet(url: url, transcript: transcript) { language in
                    importTranscript(transcript, from: url, language: language)
                }
            }
        }
        // An alert rather than the footer the pipeline errors into: this one
        // answers a file the user just picked, and has nothing to say a moment
        // later.
        .alert(
            importError?.errorDescription ?? "Couldn't import the transcript.",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            ),
            presenting: importError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(
                [error.recoverySuggestion, error.underlyingDescription]
                    .compactMap { $0 }
                    .joined(separator: "\n\n")
            )
        }
        .onChange(of: pipeline.lastFinishedMeetingID) { _, id in
            if let id { selection = .meeting(id) }
        }
        .onChange(of: pipeline.isRunning, initial: true) { _, isRunning in
            // Lets the app delegate warn before quitting mid-run.
            MacAppDelegate.isTranscribing = isRunning
        }
    }

    // MARK: - Sidebar

    private var sidebarList: some View {
        List(selection: $selection) {

            // Always present, even with nothing in it, so the button that adds
            // the first meeting has somewhere to live.
            Section {
                ForEach(filteredMeetings) { meeting in
                    NavigationLink(value: SidebarSelection.meeting(meeting.id)) {
                        MeetingRow(meeting: meeting)
                    }
                    .contextMenu {
                        Button("Reveal Audio in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([meeting.audioURL])
                        }
                        .disabled(!meeting.audioExists)

                        Divider()

                        Button("Delete", role: .destructive) {
                            meetingStore.delete(meeting.id)
                        }
                    }
                }
            } header: {
                HStack(spacing: 4) {
                    Text("Meetings")
                    Spacer()
                    Menu {
                        Button("Transcribe Recording…") {
                            importing = .recording
                        }
                        Button("Record a Meeting…") {
                            openWindow(id: RecorderWindow.windowID)
                        }
                        Divider()
                        Button("Import Transcript…") {
                            importing = .transcript
                        }
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    // Without this the menu takes the width the header offers
                    // it and the plus drifts away from the trailing edge.
                    .fixedSize()
                    .help("Add a meeting")
                    .padding(.trailing, 4)
                }
            }

            Section("Library") {
                NavigationLink(value: SidebarSelection.speakers) {
                    Label("People", systemImage: "person.2")
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 340)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search transcripts")
    }

    private var filteredMeetings: [Meeting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetingStore.meetings }

        return meetingStore.meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(query)
                || meeting.speakers.contains { $0.name.localizedCaseInsensitiveContains(query) }
                || meeting.utterances.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        switch selection {
        case .meeting(let id):
            if let meeting = meetingStore.meeting(id) {
                MeetingPane(meetingID: meeting.id)
                    .id(meeting.id)
            } else {
                EmptyPane { importing = .recording }
            }
        case .speakers:
            SpeakersPane()
        case nil:
            EmptyPane { importing = .recording }
        }
    }

    // MARK: - Import

    /// Routes a dropped or chosen file: a recording to the pipeline, a
    /// transcript another app has already produced straight into the library.
    ///
    /// Split on the extension rather than on what the file turns out to hold.
    /// Reading a two-gigabyte video to establish that it isn't JSON is not a
    /// way to answer this, and "transcribe it" is the right guess for anything
    /// that isn't plainly a transcript already.
    private func offerImport(of url: URL) {
        guard url.pathExtension.lowercased() == "json" else {
            pending = .recording(
                url,
                alreadyTranscribed: meetingStore.existingMeetings(forAudioAt: url.path).first
            )
            return
        }

        // Decoded here rather than in the sheet: a sheet that can't yet say
        // what is in the file has nothing to confirm, and a file that isn't a
        // transcript should say so instead of opening one.
        do {
            pending = .transcript(url, try KlangTranscript.read(contentsOf: url))
        } catch let error as TranscriptImportError {
            importError = error
        } catch {
            importError = .unreadable(url, underlying: error)
        }
    }

    /// Files a finished transcript as a meeting and selects it, the way the
    /// pipeline's own output is selected when a run finishes.
    ///
    /// The title comes from the filename, exactly as a recording's does: a
    /// meeting has no other name, and no way to be given one afterwards.
    private func importTranscript(
        _ transcript: KlangTranscript,
        from url: URL,
        language: MeetingLanguage
    ) {
        let meeting = transcript.meeting(
            title: url.deletingPathExtension().lastPathComponent,
            language: language
        )
        meetingStore.add(meeting)
        selection = .meeting(meeting.id)
    }
}

// MARK: - Import routing

/// What the file panel is being opened for.
///
/// The two imports accept disjoint file types and mean entirely different
/// things, so the panel is filtered to one of them rather than offering both
/// and sorting it out afterwards.
private enum ImportKind {
    case recording
    case transcript

    var contentTypes: [UTType] {
        switch self {
        case .recording: [.audio, .movie]
        case .transcript: [.json]
        }
    }
}

/// A file waiting on its confirmation sheet.
private enum PendingImport: Identifiable {

    /// A recording, with the meeting already transcribed from it if there is one.
    case recording(URL, alreadyTranscribed: Meeting?)

    /// A transcript, already decoded.
    case transcript(URL, KlangTranscript)

    var id: String {
        switch self {
        case .recording(let url, _), .transcript(let url, _): url.absoluteString
        }
    }
}

// MARK: - Meeting row

private struct MeetingRow: View {

    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(meeting.importedAt.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text(Timecode.short(meeting.duration))
                if meeting.degraded != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Speaker identification did not produce a result.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview {
    Sidebar()
        .previewEnvironment()
}
#endif
