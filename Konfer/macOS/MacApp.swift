//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import AppDesign
import Sparkle

@main
struct MacApp: App {

    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Before any store reads from disk: the folder moved when the app was
        // renamed. See `LibraryMigration`.
        LibraryMigration.migrateIfNeeded()
        AppDesign.apply()
    }

    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        RecorderWindow()
        ModelDownloadsWindow()
        WelcomeWindow()
        SettingsWindow()
        AboutWindow(developedBy: "Martin Johannesson",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow(
            OpenSourceAttributions.entries,
            header: OpenSourceAttributions.header
        )
        HelpWindow()
    }
}
