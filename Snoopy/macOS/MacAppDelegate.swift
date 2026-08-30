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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        Self.shouldTerminateAppAfterLastWindowClosed
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard Self.isTranscribing else { return .terminateNow }

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
