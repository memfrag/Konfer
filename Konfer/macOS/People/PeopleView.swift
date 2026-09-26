//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The enrollment roster: people Konfer can recognise in future recordings.
///
/// A window of its own rather than a place in the main window's sidebar. It is
/// somewhere you go to tidy up, not something read beside a transcript, and as
/// a sidebar destination it took the meeting you were in out of view while you
/// did.
struct PeopleView: View {

    @Environment(SpeakerStore.self) private var speakerStore

    @State private var selection: UUID?
    @State private var renaming: SpeakerProfile?
    @State private var draftName = ""

    var body: some View {
        NavigationSplitView {
            list
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if speakerStore.profiles.isEmpty {
                empty
            } else if let id = selection, let profile = speakerStore.profile(id) {
                PersonDetail(profile: profile) { beginRename(profile) }
                    // Fresh state per person, so a note being typed can't
                    // follow the selection onto someone else.
                    .id(profile.id)
            } else {
                Text("Select a person")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("People")
        .navigationSubtitle(subtitle)
        .frame(minWidth: 600, minHeight: 380)
        .onAppear {
            if selection == nil { selection = speakerStore.profiles.first?.id }
        }
        .sheet(item: $renaming) { profile in
            renameSheet(profile)
        }
    }

    private var subtitle: String {
        let count = speakerStore.profiles.count
        return count == 1 ? "1 person" : "\(count) people"
    }

    // MARK: - Empty

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No one enrolled yet")
                .font(.title3)
            Text(
                "Name a speaker in a transcript and Konfer remembers their voice, "
                + "then suggests them in later recordings."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 340)
        }
        .padding(40)
    }

    // MARK: - List

    private var list: some View {
        List(selection: $selection) {
            ForEach(speakerStore.profiles) { profile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                    if let note = profile.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(detail(for: profile))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
                .tag(profile.id)
                .contextMenu {
                    Button("Rename…") { beginRename(profile) }
                    mergeMenu(for: profile)
                    Divider()
                    Button("Delete", role: .destructive) {
                        speakerStore.delete(profile.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func detail(for profile: SpeakerProfile) -> String {
        let meetings = profile.sampleCount == 1 ? "1 recording" : "\(profile.sampleCount) recordings"
        let date = profile.updatedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(meetings) · last heard \(date)"
    }

    @ViewBuilder
    private func mergeMenu(for profile: SpeakerProfile) -> some View {
        let others = speakerStore.profiles.filter { $0.id != profile.id }
        if !others.isEmpty {
            Menu("Same Person As") {
                ForEach(others) { other in
                    Button(other.name) {
                        speakerStore.merge(profile.id, into: other.id)
                        selection = other.id
                    }
                }
            }
        }
    }

    // MARK: - Renaming

    private func beginRename(_ profile: SpeakerProfile) {
        draftName = profile.name
        renaming = profile
    }

    private func renameSheet(_ profile: SpeakerProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Person")
                .font(.headline)
            TextField("Name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { renaming = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    speakerStore.rename(profile.id, to: draftName)
                    renaming = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

// MARK: - Person

/// One person: who they are, in the user's words, and what Konfer has heard.
private struct PersonDetail: View {

    let profile: SpeakerProfile
    let onRename: () -> Void

    @Environment(SpeakerStore.self) private var speakerStore

    @State private var note: String

    init(profile: SpeakerProfile, onRename: @escaping () -> Void) {
        self.profile = profile
        self.onRename = onRename
        _note = State(initialValue: profile.note ?? "")
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    HStack {
                        Text(profile.name)
                        Button("Rename…", action: onRename)
                            .controlSize(.small)
                    }
                }
            }

            // A section of its own with the label hidden: in a form row the
            // field sits in the trailing column, and a paragraph set flush
            // right reads like a mistake.
            Section {
                TextField(
                    "Description",
                    text: $note,
                    prompt: Text("Who they are, and how you know them"),
                    axis: .vertical
                )
                .labelsHidden()
                .lineLimit(3...8)
            } header: {
                Text("Description")
            } footer: {
                Text("Shown beside their name here, and when Konfer thinks it hears them in a recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice") {
                LabeledContent("Heard in") {
                    Text(profile.sampleCount == 1 ? "1 recording" : "\(profile.sampleCount) recordings")
                }
                LabeledContent("First heard") {
                    Text(profile.createdAt.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Last heard") {
                    Text(profile.updatedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .formStyle(.grouped)
        // Written through as it is typed, like everything else in the library.
        // There is no Save button to forget, and closing the window mid-word
        // loses nothing.
        .onChange(of: note) { _, note in
            speakerStore.setNote(note, for: profile.id)
        }
    }
}

#if DEBUG
#Preview {
    PeopleView()
        .previewEnvironment()
}
#endif
