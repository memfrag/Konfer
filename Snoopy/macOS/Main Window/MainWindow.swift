//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {

        WindowGroup {
            RootView()
                .frame(minWidth: 720, minHeight: 460)
                .appEnvironment(.default)
                .terminatesAppWhenClosed()
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            SidebarCommands()
            RecordCommand()
            ExportCommands()
            HelpCommands()
            ModelCommands()

        }
    }
}

// MARK: - Root

/// The sidebar, plus the one thing that has to happen on a first launch.
///
/// A view rather than a modifier on the scene, because the welcome check reads
/// `AppSettings` — and a `Scene` has no environment to read it from.
private struct RootView: View {

    @Environment(AppSettings.self) private var appSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Sidebar()
            .task {
                guard !appSettings.hasCompletedOnboarding else { return }
                openWindow(id: WelcomeWindow.windowID)
            }
    }
}
