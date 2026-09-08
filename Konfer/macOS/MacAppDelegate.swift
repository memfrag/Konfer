//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

class MacAppDelegate: NSObject, NSApplicationDelegate {

    // Sparkle may show its update-permission prompt before the main window
    // appears. If that prompt is the only open window, closing it would
    // otherwise terminate the app before it has even started.
    static var shouldTerminateAppAfterLastWindowClosed = false

    /// Set while a transcription is running, so quitting asks first.
    ///
    /// A run can take minutes and can't be resumed — neither FluidAudio stage
    /// is restartable partway — so quitting mid-run throws the work away.
    static var isTranscribing = false

    /// True while the quit alert is on screen.
    ///
    /// `runModal()` spins the run loop, so a second termination request can
    /// arrive while the first is still being answered. Without this it would
    /// put a second alert on top of the first.
    private var isAskingWhetherToQuit = false

    /// Whether closing the last window should quit the app.
    ///
    /// Not while a transcription is running, and the reason is a loop rather
    /// than a preference. Closing the main window mid-run used to start a
    /// termination the alert then cancelled — at which point the *alert's own
    /// window* closed, and with the main window already gone that was again
    /// the last window closing, so AppKit asked again, and again. The app
    /// never came back either, because cancelling a termination does not
    /// reopen the window that started it.
    ///
    /// So closing the window during a run simply leaves the run going, which
    /// is what the alert's "Keep Transcribing" was asking for anyway. The Dock
    /// icon brings the window back, and ⌘Q still asks before discarding.
    static func terminatesAfterLastWindowClosed(
        hasShownMainWindow: Bool,
        isTranscribing: Bool
    ) -> Bool {
        hasShownMainWindow && !isTranscribing
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.terminatesAfterLastWindowClosed(
            hasShownMainWindow: Self.shouldTerminateAppAfterLastWindowClosed,
            isTranscribing: Self.isTranscribing
        )
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard Self.isTranscribing else { return .terminateNow }
        guard !isAskingWhetherToQuit else { return .terminateCancel }

        isAskingWhetherToQuit = true
        defer { isAskingWhetherToQuit = false }

        let alert = NSAlert()
        alert.messageText = "Transcription in progress"
        alert.informativeText =
            "Quitting now discards this transcription. It can't be resumed, "
            + "so the recording would have to be transcribed again from the start."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Keep Transcribing")

        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}

// MARK: - Terminates App When Closed Modifier

extension View {

    /// Marks this view as the main window for the purposes of
    /// `applicationShouldTerminateAfterLastWindowClosed`. Once the view has
    /// appeared at least once, the app is allowed to terminate when the last
    /// window closes.
    func terminatesAppWhenClosed() -> some View {
        onAppear {
            MacAppDelegate.shouldTerminateAppAfterLastWindowClosed = true
        }
    }
}
