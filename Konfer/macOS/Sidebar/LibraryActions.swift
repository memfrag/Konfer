//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// What the sidebar can do with a transcript or folder as a file on disk:
/// show it in Finder, open a terminal there, and copy its path.
///
/// Possible because the library is real folders of files named after their
/// meetings, which is also why these are worth having — the files are
/// something to work with, not an app's private storage.
@MainActor
enum LibraryActions {

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens a new terminal window in `folder`.
    ///
    /// Handed to the terminal as a file to open, which Terminal, iTerm2,
    /// Ghostty and Warp all answer with a window at that folder — no script,
    /// and no Apple Events permission to ask for.
    static func openInTerminal(_ folder: URL) {
        guard let terminal = terminalApplication else { return }
        NSWorkspace.shared.open(
            [folder],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// Copies a path as plain text, as Finder's Copy as Pathname does:
    /// unquoted, so it pastes as the path it is.
    static func copyPath(of url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    // MARK: - The terminal

    /// The terminal to open, which is the system's rather than Konfer's to
    /// choose.
    ///
    /// macOS has no "default terminal" setting as such. The nearest thing is
    /// the app that opens a Unix executable: what double-clicking a script in
    /// Finder launches, what Finder's Open With ▸ Change All sets, and what
    /// iTerm2's Make iTerm2 Default Term changes. Following it means a user
    /// who has already made that choice has made it for Konfer too. The
    /// shell-script type would be the wrong question — on the Mac this was
    /// written on it answers Nova, an editor.
    static var terminalApplication: URL? {
        NSWorkspace.shared.urlForApplication(toOpen: .unixExecutable)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    /// The terminal's name for the menu, "Terminal" when there is none to ask.
    static var terminalName: String {
        guard let terminal = terminalApplication else { return "Terminal" }
        return FileManager.default.displayName(atPath: terminal.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
