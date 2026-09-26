//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Konfer Help, opened from the Help menu.
///
/// The pages are Markdown files bundled with the app — see ``HelpTopic`` —
/// rendered natively by MarkdownUI rather than in a web view, so they follow
/// the system's appearance and text size like every other window.
struct HelpWindow: Scene {

    static let windowID = "help"

    var body: some Scene {
        Window("Konfer Help", id: Self.windowID) {
            HelpView()
        }
        .commandsRemoved() // Don't show window in Windows menu
        .defaultPosition(.center)
        .defaultSize(width: 820, height: 580)
        .windowResizability(.contentMinSize)
    }
}
