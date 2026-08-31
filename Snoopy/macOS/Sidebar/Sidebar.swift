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
    @State private var isShowingImporter = false
    @State private var pendingImport: URL?
    @State private var duplicateOf: Meeting?

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
            isPresented: $isShowingImporter,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                offerImport(of: url)
            }
        }
        .sheet(item: $pendingImport) { url in
            ImportSheet(url: url, alreadyTranscribed: duplicateOf) { language, speakers in
                pipeline.enqueue(url, language: language, expectedSpeakers: speakers)
            } onOpenExisting: { meeting in
                selection = .meeting(meeting.id)
            }
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
                            isShowingImporter = true
                        }
                        Button("Record a Meeting…") {
                            openWindow(id: RecorderWindow.windowID)
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
                EmptyPane { isShowingImporter = true }
            }
        case .speakers:
            SpeakersPane()
        case nil:
            EmptyPane { isShowingImporter = true }
        }
    }

    // MARK: - Import

    private func offerImport(of url: URL) {
        duplicateOf = meetingStore.existingMeetings(forAudioAt: url.path).first
        pendingImport = url
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

// MARK: - URL identity

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if DEBUG
#Preview {
    Sidebar()
        .previewEnvironment()
}
#endif
