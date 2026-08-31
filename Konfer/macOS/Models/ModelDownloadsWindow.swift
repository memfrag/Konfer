//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The models, in their own window.
///
/// Separate from Settings for the same reason the recorder is: a multi-gigabyte
/// download is something you start and then leave running while you do
/// something else, and a settings window you have to keep open to watch is a
/// settings window in the way.
struct ModelDownloadsWindow: Scene {

    static let windowID = "model-downloads"

    var body: some Scene {
        Window("Models", id: Self.windowID) {
            // The environment is injected here, inside the window — a Scene
            // itself has no access to it.
            ModelDownloadsView()
                .appEnvironment(.default)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
