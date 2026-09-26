//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Where a new meeting will be filed, in the sheets that make one.
///
/// Flat and indented by depth, like the sidebar's Move To menu, so the two
/// places that choose a folder read the same.
struct FolderPicker: View {

    @Binding var folder: MeetingFolder

    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        Picker("Folder:", selection: $folder) {
            Label("Top Level", systemImage: "tray.full").tag(MeetingFolder.root)
            if !meetingStore.folders.isEmpty {
                Divider()
            }
            ForEach(meetingStore.folders, id: \.self) { folder in
                Text(String(repeating: "    ", count: folder.components.count - 1) + folder.name)
                    .tag(folder)
            }
        }
    }
}
