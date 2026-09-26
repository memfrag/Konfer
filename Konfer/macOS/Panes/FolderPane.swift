//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// What the detail column shows while a folder is selected.
///
/// A folder is somewhere to file meetings, not something to read, so this
/// says what is in it and how things get there. Selecting one mostly matters
/// for what it sets up: New Folder makes the new one inside it.
struct FolderPane: View {

    let folder: MeetingFolder

    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        Pane {
            VStack(spacing: 14) {
                Image(systemName: "folder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    Text(folder.name)
                        .font(.title3)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("Drag meetings onto a folder in the sidebar to file them there.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
        }
        .navigationTitle(folder.name)
    }

    private var summary: String {
        let count = meetingStore.meetingCount(in: folder)
        return count == 1 ? "1 meeting" : "\(count) meetings"
    }
}
