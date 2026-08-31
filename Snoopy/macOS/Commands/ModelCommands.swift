//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Window ▸ Models
///
/// A multi-gigabyte download deserves a way back to it that doesn't involve
/// remembering which settings tab it was behind.
struct ModelCommands: Commands {

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Models") {
                openWindow(id: ModelDownloadsWindow.windowID)
            }
        }
    }
}
