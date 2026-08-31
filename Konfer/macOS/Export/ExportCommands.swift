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
        }
    }
}

// MARK: - Focused value

/// Lets the transcript pane offer the frontmost meeting to the menu bar.
struct ExportableMeeting: Equatable {

    let id: UUID
    let export: @MainActor (TranscriptExporter.Format) -> Void

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
