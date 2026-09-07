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
                        meeting?.export(format)
                    }
                    .disabled(meeting == nil)
                }
            }
            // Not one of the formats above: those render a transcript to data
            // in memory, and this copies a recording. Sidecar subtitles are for
            // players that read them; this is for QuickTime, which doesn't.
            Section {
                Button("Export Video with Subtitles…") {
                    meeting?.exportVideo()
                }
                .disabled(meeting?.canExportVideo != true)
            }
        }
    }
}

// MARK: - Focused value

/// Lets the transcript pane offer the frontmost meeting to the menu bar.
struct ExportableMeeting: Equatable {

    let id: UUID
    let export: @MainActor (TranscriptExporter.Format) -> Void

    /// Writes a copy of the recording with the subtitles inside it.
    let exportVideo: @MainActor () -> Void

    /// False for an audio-only meeting, and for one whose recording has moved.
    /// Subtitles need a picture to sit on.
    let canExportVideo: Bool

    func callAsFunction(_ format: TranscriptExporter.Format) {
        export(format)
    }

    static func == (lhs: ExportableMeeting, rhs: ExportableMeeting) -> Bool {
        lhs.id == rhs.id
    }
}

extension FocusedValues {
    @Entry var exportableMeeting: ExportableMeeting?
}
