//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Edit ▸ Find
///
/// Real menu items rather than shortcuts hidden on invisible buttons, so ⌘F is
/// discoverable and greys out when there is no transcript to search.
struct FindCommands: Commands {

    /// The find session of whichever transcript is focused, if any.
    @FocusedValue(\.transcriptFind) private var find

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Section {
                // Find and replace are one bar, so there is one command.
                Button("Find…") {
                    find?.present()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(find == nil)

                Button("Find Next") { find?.next() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(find?.hasMatches != true)

                Button("Find Previous") { find?.previous() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(find?.hasMatches != true)
            }
        }
    }
}
