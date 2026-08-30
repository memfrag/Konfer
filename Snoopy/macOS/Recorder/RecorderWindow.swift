//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The recorder, in its own window.
///
/// Separate from the main window because recording and reading a transcript are
/// different activities: one is set up once and left alone, the other is
/// browsed. A recording in progress should stay visible while you read
/// something else.
struct RecorderWindow: Scene {

    static let windowID = "recorder"

    var body: some Scene {
        Window("Record", id: Self.windowID) {
            // The environment is injected here, inside the window — a Scene
            // itself has no access to it.
            RecorderView()
                .appEnvironment(.default)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
