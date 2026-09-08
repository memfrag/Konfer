//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Whether closing the last window may start a termination.
///
/// The rule looks like a preference and is not one. Letting a window close
/// start a termination that the "Transcription in progress" alert then
/// cancelled put the app in a loop: the alert's own window closing was, with
/// the main window already gone, the last window closing again.
@MainActor
struct QuitDuringTranscriptionTests {

    @Test("Closing the last window quits, once the main window has been seen")
    func quitsNormally() {
        #expect(
            MacAppDelegate.terminatesAfterLastWindowClosed(
                hasShownMainWindow: true, isTranscribing: false
            )
        )
    }

    @Test("Closing a window before the main one has appeared never quits")
    func waitsForTheMainWindow() {
        // Sparkle's update prompt can be the only window open at launch.
        #expect(
            !MacAppDelegate.terminatesAfterLastWindowClosed(
                hasShownMainWindow: false, isTranscribing: false
            )
        )
    }

    @Test("Closing the window during a transcription does not start a quit")
    func doesNotQuitWhileTranscribing() {
        #expect(
            !MacAppDelegate.terminatesAfterLastWindowClosed(
                hasShownMainWindow: true, isTranscribing: true
            )
        )
    }

    @Test("The alert's own window closing cannot ask again while the run continues")
    func theAlertCannotRetriggerItself() {
        // The loop, stated as the sequence that produced it: the main window
        // closes, the alert is answered with Keep Transcribing, and the alert
        // window closes in its turn. That third moment must not ask again.
        let afterMainWindowClosed = MacAppDelegate.terminatesAfterLastWindowClosed(
            hasShownMainWindow: true, isTranscribing: true
        )
        let afterAlertClosed = MacAppDelegate.terminatesAfterLastWindowClosed(
            hasShownMainWindow: true, isTranscribing: true
        )

        #expect(!afterMainWindowClosed)
        #expect(!afterAlertClosed)
    }

    @Test("Once the run finishes, closing the window quits again")
    func quitsAgainAfterTheRun() {
        #expect(
            MacAppDelegate.terminatesAfterLastWindowClosed(
                hasShownMainWindow: true, isTranscribing: false
            )
        )
    }
}
