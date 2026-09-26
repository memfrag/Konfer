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
    @Environment(LibrarySelection.self) private var librarySelection

    @State private var searchText: String = ""
    @State private var selection: SidebarSelection?

    /// What the file panel is open for, if it is open.
    @State private var importing: ImportKind?

    /// The file waiting on its confirmation sheet.
    @State private var pending: PendingImport?

    /// A transcript file that turned out not to be one.
    @State private var importError: TranscriptImportError?

    /// The meeting or folder whose row is currently a text field, and what
    /// has been typed into it.
    @State private var renaming: SidebarSelection?
    @State private var renameDraft = ""
    @FocusState private var isRenameFieldFocused: Bool

    /// Which folders are open.
    ///
    /// Held here and only copied to scene storage, to survive a relaunch:
    /// outside a scene — a preview, a test — scene storage ignores writes,
    /// and a folder that won't open is a much worse failure than one that
    /// forgets it was open.
    @State private var expanded: Set<MeetingFolder> = []

    /// ``expanded`` as saved: one path per line, its folders joined by
    /// slashes — the one character no folder name on disk can contain.
    @SceneStorage("expandedFolders") private var savedExpandedFolders = ""

    var body: some View {
        NavigationSplitView {
            sidebarList
        } detail: {
            detail
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Files only: a dragged link is not a recording.
            guard let url = urls.first, url.isFileURL else { return false }
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
                // An imported file has no known channel layout, so it is never
                // two-sided and the speakers question does not apply.
                ImportSheet(url: url, alreadyTranscribed: alreadyTranscribed) { language, speakers, trim, _, folder in
                    pipeline.enqueue(
                        url,
                        language: language,
                        expectedSpeakers: speakers,
                        trim: trim,
                        folder: folder
                    )
                } onOpenExisting: { meeting in
                    selection = .meeting(meeting.id)
                }
            case .transcript(let url, let transcript):
                TranscriptImportSheet(url: url, transcript: transcript) { language, folder in
                    importTranscript(transcript, from: url, language: language, folder: folder)
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
            if let id { reveal(id) }
        }
        // Someone may have filed meetings in Finder while Konfer was in the
        // background. Only changed files are read again, so this is cheap.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            meetingStore.reload()
            forgetVanishedFolders()
        }
        .onAppear {
            expanded = Set(savedExpandedFolders.split(separator: "\n").map {
                MeetingFolder($0.split(separator: "/").map(String.init))
            })
        }
        // What the Transcribe sheet's folder picker starts on, including the
        // one the Recorder window opens. `selectedFolder` follows a folder
        // through a rename, since the selection does.
        .onChange(of: selection, initial: true) { _, _ in
            librarySelection.folder = selectedFolder
        }
        .onChange(of: expanded) { _, expanded in
            savedExpandedFolders = expanded
                .map { $0.components.joined(separator: "/") }
                .sorted()
                .joined(separator: "\n")
        }
        .onChange(of: pipeline.isRunning, initial: true) { _, isRunning in
            // Lets the app delegate warn before quitting mid-run.
            MacAppDelegate.isTranscribing = isRunning
        }
    }

    /// Export without opening the meeting first.
    ///
    /// Flat rather than a submenu per language: two levels is already as deep
    /// as a context menu should go, and naming the language on the item says
    /// which is which without opening anything further. Video export is not
    /// here — knowing whether a recording has a picture means reading the
    /// file, which is a probe per row the list would have to make for every
    /// meeting to draw one menu.
    @ViewBuilder
    private func exportMenu(for meeting: Meeting) -> some View {
        Menu("Export") {
            ForEach(TranscriptExporter.Format.allCases) { format in
                Button("\(format.displayName)…") {
                    MeetingExport.save(meeting, format: format)
                }
            }

            if let target = meeting.translationTarget {
                Divider()
                ForEach(TranscriptExporter.Format.allCases.filter(\.hasTranslatedVariant)) { format in
                    Button("\(format.displayName) (\(target.displayName))…") {
                        MeetingExport.save(meeting, format: format, rendering: .translated)
                    }
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarList: some View {
        List(selection: $selection) {

            // Always present, even with nothing in it, so the button that adds
            // the first meeting has somewhere to live.
            Section {
                if isSearching {
                    // Search looks through every folder at once, and a match
                    // is only useful if you can see where it was filed.
                    ForEach(filteredMeetings) { meeting in
                        meetingRow(meeting, showsFolder: true)
                    }
                } else {
                    rows(in: .root)
                }
            } header: {
                header
                    // The header stands in for the top level, which has no
                    // row of its own to drop onto.
                    .dropDestination(for: SidebarItem.self) { items, _ in
                        file(items, into: .root)
                    }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 340)
        // On the sidebar's own column, which is what puts it in the part of
        // the toolbar above the sidebar rather than over the transcript.
        .toolbar {
            ToolbarItem {
                Button("People", systemImage: "person.2") {
                    openWindow(id: PeopleWindow.windowID)
                }
                .help("People Konfer recognises")
            }
        }
        .safeAreaBar(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search transcripts")
    }

    private var header: some View {
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
                Divider()
                Button("New Folder") {
                    newFolder(in: selectedFolder)
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
            .help("Add a meeting or a folder")
            .padding(.trailing, 4)
        }
    }

    /// A folder's rows: its folders first, then its meetings, as in Mail.
    ///
    /// Type-erased because it contains itself — a folder's rows include each
    /// subfolder's.
    private func rows(in folder: MeetingFolder) -> AnyView {
        AnyView(Group {
            ForEach(meetingStore.subfolders(of: folder), id: \.self) { child in
                DisclosureGroup(isExpanded: expansion(of: child)) {
                    rows(in: child)
                } label: {
                    folderRow(child)
                }
            }
            ForEach(meetingStore.meetings(in: folder)) { meeting in
                meetingRow(meeting, showsFolder: false)
            }
        })
    }

    @ViewBuilder
    private func meetingRow(_ meeting: Meeting, showsFolder: Bool) -> some View {
        // The whole row swaps to the field rather than growing one inside the
        // link: a text field inside a `NavigationLink` spends its clicks on the
        // link instead of on the text.
        if renaming == .meeting(meeting.id) {
            renameField
        } else {
            NavigationLink(value: SidebarSelection.meeting(meeting.id)) {
                MeetingRow(
                    meeting: meeting,
                    folder: showsFolder ? meetingStore.folder(of: meeting.id) : nil
                )
            }
            .draggable(SidebarItem.meeting(meeting.id))
            // Dropped onto a meeting means dropped into the folder it is in,
            // as in a Finder list — so there is always a row to aim for.
            .dropDestination(for: SidebarItem.self) { items, _ in
                file(items, into: meetingStore.folder(of: meeting.id) ?? .root)
            }
            .contextMenu {
                Button("Rename") { beginRename(meeting) }

                moveMenu(for: .meeting(meeting.id), from: meetingStore.folder(of: meeting.id) ?? .root)
                Button("New Folder with Meeting") { newFolder(containing: meeting.id) }

                Button("Reveal Audio in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([meeting.audioURL])
                }
                .disabled(!meeting.audioExists)

                Divider()

                exportMenu(for: meeting)

                Divider()

                Button("Delete", role: .destructive) {
                    meetingStore.delete(meeting.id)
                }
            }
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: MeetingFolder) -> some View {
        if renaming == .folder(folder) {
            renameField
        } else {
            Label(folder.name, systemImage: "folder")
                .tag(SidebarSelection.folder(folder))
                .draggable(SidebarItem.folder(folder.components))
                .dropDestination(for: SidebarItem.self) { items, _ in
                    file(items, into: folder)
                }
                .contextMenu {
                    Button("New Folder") { newFolder(in: folder) }
                    Button("Rename") { beginRename(folder) }
                    moveMenu(for: .folder(folder), from: folder.parent ?? .root)

                    Divider()

                    // Nothing is lost by it, so it asks nothing: the meetings
                    // and folders inside move up to take its place.
                    Button("Delete Folder") { deleteFolder(folder) }
                        .help("Its meetings and folders move up a level.")
                }
        }
    }

    /// Somewhere else to file a meeting or folder, for when dragging is
    /// awkward — a long list, or a keyboard.
    ///
    /// Flat, indented by depth: a submenu per level would put the folder you
    /// want three hovers away.
    private func moveMenu(for item: SidebarSelection, from current: MeetingFolder) -> some View {
        Menu("Move To") {
            Button("Top Level") { move(item, to: .root) }
                .disabled(current == .root)
            if !meetingStore.folders.isEmpty {
                Divider()
            }
            ForEach(meetingStore.folders, id: \.self) { folder in
                Button(String(repeating: "    ", count: folder.components.count - 1) + folder.name) {
                    move(item, to: folder)
                }
                .disabled(folder == current || {
                    // A folder can't go into itself or anything inside it.
                    if case .folder(let moving) = item { return moving.contains(folder) }
                    return false
                }())
            }
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    // MARK: - Folders

    /// Where New Folder puts the folder: inside the selected one, or beside
    /// the selected meeting.
    private var selectedFolder: MeetingFolder {
        switch selection {
        case .folder(let folder): folder
        case .meeting(let id): meetingStore.folder(of: id) ?? .root
        case nil: .root
        }
    }

    /// Makes a folder and puts its name straight into a text field, as Finder
    /// does — a folder is almost never meant to be called "New Folder".
    private func newFolder(in parent: MeetingFolder) {
        guard let folder = meetingStore.createFolder(in: parent) else { return }
        setExpanded(parent, true)
        selection = .folder(folder)
        beginRename(folder)
    }

    /// Finder's New Folder with Selection: a folder beside the meeting, with
    /// the meeting in it, named straight away.
    ///
    /// The meeting stays selected, so the transcript you were reading stays
    /// on screen while you name where it now lives.
    private func newFolder(containing id: UUID) {
        let parent = meetingStore.folder(of: id) ?? .root
        guard let folder = meetingStore.createFolder(in: parent) else { return }
        meetingStore.move(id, to: folder)
        setExpanded(parent, true)
        setExpanded(folder, true)
        beginRename(folder)
    }

    private func deleteFolder(_ folder: MeetingFolder) {
        meetingStore.deleteFolder(folder)
        if case .folder(let selected) = selection, folder.contains(selected) {
            selection = folder.parent.flatMap { $0.isRoot ? nil : .folder($0) }
        }
        forgetVanishedFolders()
    }

    private func file(_ items: [SidebarItem], into folder: MeetingFolder) -> Bool {
        for item in items {
            switch item {
            case .meeting(let id): move(.meeting(id), to: folder)
            case .folder(let components): move(.folder(MeetingFolder(components)), to: folder)
            }
        }
        return !items.isEmpty
    }

    private func move(_ item: SidebarSelection, to folder: MeetingFolder) {
        switch item {
        case .meeting(let id):
            meetingStore.move(id, to: folder)
        case .folder(let moving):
            guard let moved = meetingStore.moveFolder(moving, into: folder) else { return }
            follow(moving, to: moved)
        }
        // Open where it went, so what was just filed doesn't vanish into a
        // closed folder.
        setExpanded(folder, true)
    }

    /// Keeps the selection, the field being typed in and the open folders
    /// pointing at a folder that has been renamed or moved.
    private func follow(_ old: MeetingFolder, to new: MeetingFolder) {
        if case .folder(let selected) = selection {
            selection = .folder(selected.moving(old, to: new))
        }
        expanded = Set(expanded.map { $0.moving(old, to: new) })
    }

    /// Selects a meeting and opens every folder above it, so a transcription
    /// that just finished is on screen wherever it was filed.
    private func reveal(_ id: UUID) {
        var folder = meetingStore.folder(of: id)
        while let current = folder, !current.isRoot {
            setExpanded(current, true)
            folder = current.parent
        }
        selection = .meeting(id)
    }

    /// Drops what no longer exists — removed here, or in Finder — from the
    /// selection and the open folders.
    private func forgetVanishedFolders() {
        let existing = Set(meetingStore.folders)
        if case .folder(let selected) = selection, !existing.contains(selected) {
            selection = nil
        }
        let kept = expanded.intersection(existing)
        if kept != expanded { expanded = kept }
    }

    // MARK: - Open folders

    private func expansion(of folder: MeetingFolder) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(folder) },
            set: { setExpanded(folder, $0) }
        )
    }

    private func setExpanded(_ folder: MeetingFolder, _ isExpanded: Bool) {
        guard !folder.isRoot else { return }
        if isExpanded { expanded.insert(folder) } else { expanded.remove(folder) }
    }

    // MARK: - Renaming

    /// The row a meeting or folder is renamed in.
    ///
    /// Return commits and Escape abandons, and so does clicking away — the
    /// Finder's terms, because this looks exactly like renaming a file there
    /// and anything else would be a surprise. Committing an empty name is left
    /// to ``Meeting/rename(to:)`` and ``MeetingStore/renameFolder(_:to:)``,
    /// which keep the old one.
    private var renameField: some View {
        TextField("Name", text: $renameDraft)
            .textFieldStyle(.roundedBorder)
            .focused($isRenameFieldFocused)
            .onSubmit { commitRename() }
            .onExitCommand { renaming = nil }
            .onAppear {
                // A turn later, not in this one: a field focused before it has
                // joined the responder chain is focused and then immediately
                // isn't, and the row sits there refusing to take a keystroke.
                Task { isRenameFieldFocused = true }
            }
            .onChange(of: isRenameFieldFocused) { _, isFocused in
                // Reached by clicking away. Return and Escape have both
                // already cleared `renaming`, so the commit below is a no-op
                // for them rather than a second one.
                if !isFocused { commitRename() }
            }
            .padding(.vertical, 2)
    }

    private func beginRename(_ meeting: Meeting) {
        renameDraft = meeting.title
        renaming = .meeting(meeting.id)
    }

    private func beginRename(_ folder: MeetingFolder) {
        renameDraft = folder.name
        renaming = .folder(folder)
    }

    private func commitRename() {
        guard let target = renaming else { return }
        renaming = nil
        switch target {
        case .meeting(let id):
            meetingStore.modify(id) { $0.rename(to: renameDraft) }
        case .folder(let folder):
            let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != folder.name,
                  let renamed = meetingStore.renameFolder(folder, to: trimmed)
            else { return }
            follow(folder, to: renamed)
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
        case .folder(let folder):
            FolderPane(folder: folder)
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
        language: MeetingLanguage,
        folder: MeetingFolder
    ) {
        let meeting = transcript.meeting(
            title: url.deletingPathExtension().lastPathComponent,
            language: language
        )
        meetingStore.add(meeting, in: folder)
        reveal(meeting.id)
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

    /// Shown under the title in search results, which gather meetings from
    /// every folder into one list.
    var folder: MeetingFolder?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .lineLimit(1)
            if let folder, !folder.isRoot {
                Label(folder.components.joined(separator: " › "), systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
