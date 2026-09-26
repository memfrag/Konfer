//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import Observation

/// The folder the main window's sidebar is in, for everything that files a
/// new meeting without being able to see the sidebar.
///
/// Shared through ``AppEnvironment`` rather than kept in the sidebar's own
/// state, because the Recorder is a window of its own: a recording finished
/// there is filed by what the sidebar had selected, and it has no other way
/// to know.
@Observable @MainActor
final class LibrarySelection {

    /// The selected folder, or the folder of the selected meeting.
    var folder: MeetingFolder = .root

    /// Where the folder picker starts, per Settings ▸ Transcription.
    ///
    /// The top level when the selected folder has gone since it was selected,
    /// renamed or deleted in Finder — never a folder that isn't there.
    func folderForNewMeeting(settings: AppSettings, in store: MeetingStore) -> MeetingFolder {
        guard settings.newMeetingFolder == .selectedFolder,
              store.folders.contains(folder)
        else { return .root }
        return folder
    }
}
