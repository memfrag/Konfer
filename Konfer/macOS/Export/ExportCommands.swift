//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// File ▸ Export, wired to whichever meeting is selected.
struct ExportCommands: Commands {

    @FocusedValue(\.exportableMeeting) private var meeting

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Section {
                ForEach(TranscriptExporter.Format.allCases) { format in
                    Button("Export as \(format.displayName)…") {
                        meeting?.export(format, .original)
                    }
                    .disabled(meeting == nil)
                }
            }
            // Not one of the formats above: those render a transcript to data
            // in memory, and this copies a recording. Sidecar subtitles are for
            // players that read them; this is for QuickTime, which doesn't.
            Section {
                Button("Export Video with Subtitles…") {
                    meeting?.exportVideo(.original)
                }
                .disabled(meeting?.canExportVideo != true)
            }
            // One submenu rather than a second flat list of five: the same
            // formats twice over would double the length of File ▸ Export for
            // every meeting, translated or not. Named after the language, so
            // the menu says which one without being opened. JSON is absent
            // because it already carries both texts — a second file would be
            // the same bytes under a longer name.
            Section {
                Menu(meeting?.translationTarget.map { "Export in \($0.displayName)" }
                     ?? "Export Translation") {
                    ForEach(TranscriptExporter.Format.allCases.filter(\.hasTranslatedVariant)) { format in
                        Button("\(format.displayName)…") {
                            meeting?.export(format, .translated)
                        }
                    }
                    Divider()
                    Button("Video with Subtitles…") {
                        meeting?.exportVideo(.translated)
                    }
                    .disabled(meeting?.canExportVideo != true)
                }
                .disabled(meeting?.translationTarget == nil)
            }
        }
    }
}

// MARK: - Focused value

/// Lets the transcript pane offer the frontmost meeting to the menu bar.
struct ExportableMeeting: Equatable {

    let id: UUID
    let export: @MainActor (TranscriptExporter.Format, TranscriptRendering) -> Void

    /// Writes a copy of the recording with the subtitles inside it.
    let exportVideo: @MainActor (TranscriptRendering) -> Void

    /// False for an audio-only meeting, and for one whose recording has moved.
    /// Subtitles need a picture to sit on.
    let canExportVideo: Bool

    /// The language a translation exists in, so the menu can name it and
    /// disable itself when there is none.
    let translationTarget: MeetingLanguage?

    func callAsFunction(
        _ format: TranscriptExporter.Format,
        _ rendering: TranscriptRendering = .original
    ) {
        export(format, rendering)
    }

    /// Every field the menu reads, and none of the closures, which cannot be
    /// compared.
    ///
    /// The id alone is not enough, and quietly so: SwiftUI only republishes a
    /// focused value that compares unequal, so a meeting whose translation has
    /// just finished would still be offered to the menu bar as the meeting it
    /// was a minute ago — with the translated exports greyed out and no way to
    /// reach them short of selecting another meeting and coming back. The same
    /// went for `canExportVideo`, which changes when the video probe resolves
    /// and when an export finishes.
    static func == (lhs: ExportableMeeting, rhs: ExportableMeeting) -> Bool {
        lhs.id == rhs.id
            && lhs.canExportVideo == rhs.canExportVideo
            && lhs.translationTarget == rhs.translationTarget
    }
}

extension FocusedValues {
    @Entry var exportableMeeting: ExportableMeeting?
}
