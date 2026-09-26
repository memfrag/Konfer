//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// What the sidebar can have selected.
///
/// The boilerplate's fixed enum of panes doesn't fit an app whose navigation is
/// a list of documents, so meetings carry their id and folders their path.
/// People used to be a case here too and is now a window of its own; see
/// ``PeopleWindow``.
enum SidebarSelection: Hashable {
    case meeting(UUID)
    case folder(MeetingFolder)
}
