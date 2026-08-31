//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The first-run screen, in its own window.
///
/// Shown once, from ``MainWindow``, and never again — see
/// ``AppSettings/hasCompletedOnboarding``.
struct WelcomeWindow: Scene {

    static let windowID = "welcome"

    var body: some Scene {
        Window("Welcome", id: Self.windowID) {
            WelcomeWindowContent()
                .appEnvironment(.default)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// Closes the welcome window, and hands the user to the downloads window when
/// there is something to watch.
private struct WelcomeWindowContent: View {

    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        WelcomeView { openDownloads in
            if openDownloads {
                openWindow(id: ModelDownloadsWindow.windowID)
            }
            dismissWindow(id: WelcomeWindow.windowID)
        }
    }
}
