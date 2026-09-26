//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// View ▸ Show / Hide Transcription Cuts
///
/// The yellow ticks in the waveform mark where a long recording was cut into
/// slices to transcribe them side by side. They are for diagnosing a word
/// lost at a cut, and measured, a cut in real silence loses nothing — so
/// they are hidden unless asked for.
///
/// Kept in `@AppStorage` rather than `AppSettings`: a `Commands` can't read
/// the environment the app's views are given, and storage is what both the
/// menu and the waveform observe, so each follows the other at once.
struct TranscriptionCutsCommand: Commands {

    @AppStorage(TranscriptionCutsCommand.storageKey) private var showsCuts = false

    static let storageKey = "showsTranscriptionCuts"

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(showsCuts ? "Hide Transcription Cuts" : "Show Transcription Cuts") {
                showsCuts.toggle()
            }
        }
    }
}
