//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Saving a transcript from somewhere that isn't the transcript.
///
/// The pane exports through `fileExporter`, which is right there: it has the
/// meeting open, and a sheet on its own window is where the save belongs. The
/// sidebar has neither. A row you right-click is not necessarily the row you
/// are reading, so the export has to name its meeting rather than take the
/// focused one, and a list has no document window to hang a sheet from.
///
/// What both share is the naming rule, which lives here so a transcript saved
/// from the sidebar and the same one saved from the menu bar cannot land under
/// different names.
@MainActor
enum MeetingExport {

    /// What the save panel offers to call the file.
    ///
    /// The language goes in the name for a translated export, so the two
    /// renderings of one meeting do not overwrite each other and neither has
    /// to be opened to tell which is which.
    static func filename(
        for meeting: Meeting,
        format: TranscriptExporter.Format,
        rendering: TranscriptRendering
    ) -> String {
        guard rendering == .translated, let target = meeting.translationTarget else {
            return "\(meeting.title).\(format.fileExtension)"
        }
        return "\(meeting.title) (\(target.displayName)).\(format.fileExtension)"
    }

    static func contentType(for format: TranscriptExporter.Format) -> UTType {
        switch format {
        case .markdown: .plainText
        case .json: .json
        case .webVTT: TranscriptDocument.webVTT
        case .subRip: TranscriptDocument.subRip
        }
    }

    /// Asks where to put the transcript, then writes it.
    ///
    /// Renders before asking: a transcript is a few hundred kilobytes and
    /// there is no sense putting up a panel for an export that was going to
    /// fail anyway.
    static func save(
        _ meeting: Meeting,
        format: TranscriptExporter.Format,
        rendering: TranscriptRendering = .original
    ) {
        let data: Data
        do {
            data = try TranscriptExporter.data(for: meeting, format: format, rendering: rendering)
        } catch {
            present(error, verb: "render", meeting: meeting)
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export \(format.displayName)"
        panel.nameFieldStringValue = filename(for: meeting, format: format, rendering: rendering)
        panel.allowedContentTypes = [contentType(for: format)]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            present(error, verb: "save", meeting: meeting)
        }
    }

    /// An alert rather than the sidebar footer, which belongs to work that
    /// takes long enough to watch. This one is over before the panel closes,
    /// so a failure has to speak where the user is looking.
    private static func present(_ error: Error, verb: String, meeting: Meeting) {
        let alert = NSAlert()
        alert.messageText = "Couldn't \(verb) \(meeting.title)."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
