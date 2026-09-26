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

    // Not started while hosting tests: a test run shouldn't check for
    // updates, record that it did in the user's preferences, or put an
    // update dialog in front of the runner. See `TestHost`.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: !TestHost.isHostingTests,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Before any store reads from disk: the folder moved when the app was
        // renamed. See `LibraryMigration`. Not while hosting tests, which
        // run on a throwaway library — see `TestHost`.
        if !TestHost.isHostingTests {
            LibraryMigration.migrateIfNeeded()
        }
        AppDesign.apply()
    }

    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        RecorderWindow()
        ModelDownloadsWindow()
        PeopleWindow()
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
