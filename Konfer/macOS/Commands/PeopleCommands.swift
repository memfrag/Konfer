//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Window ▸ People
///
/// The toolbar button is the obvious way in, but a toolbar can be hidden and
/// is no help from the keyboard.
struct PeopleCommands: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("People") {
                openWindow(id: PeopleWindow.windowID)
            }
        }
    }
}
