//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The enrollment roster: people Snoopy can recognise in future recordings.
struct SpeakersPane: View {

    @Environment(SpeakerStore.self) private var speakerStore

    @State private var selection: UUID?
    @State private var renaming: SpeakerProfile?
    @State private var draftName = ""

    var body: some View {
        Pane {
            if speakerStore.profiles.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle("People")
        .navigationSubtitle(subtitle)
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
                "Name a speaker in a transcript and Snoopy remembers their voice, "
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
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                        Text(detail(for: profile))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
                .tag(profile.id)
                .contextMenu {
                    Button("Rename…") {
                        draftName = profile.name
                        renaming = profile
                    }
                    mergeMenu(for: profile)
                    Divider()
                    Button("Delete", role: .destructive) {
                        speakerStore.delete(profile.id)
                    }
                }
            }
        }
        .sheet(item: $renaming) { profile in
            renameSheet(profile)
        }
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
                    }
                }
            }
        }
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

#if DEBUG
#Preview {
    SpeakersPane()
        .previewEnvironment()
}
#endif
