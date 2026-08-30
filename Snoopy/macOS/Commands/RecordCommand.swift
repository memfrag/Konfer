//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// File ▸ New Recording…
struct RecordCommand: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Owns the File ▸ New slot outright. Snoopy has no notion of an empty
        // new document — a meeting only exists once something was recorded or
        // transcribed — so "New Recording…" is what belongs here.
        CommandGroup(replacing: .newItem) {
            Button("New Recording…") {
                openWindow(id: RecorderWindow.windowID)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
