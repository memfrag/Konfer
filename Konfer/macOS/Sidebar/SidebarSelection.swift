//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// What the sidebar can have selected.
///
/// The boilerplate's fixed enum of panes doesn't fit an app whose navigation is
/// a list of documents, so meetings carry their id. People used to be a second
/// case here and is now a window of its own; see ``PeopleWindow``.
enum SidebarSelection: Hashable {
    case meeting(UUID)
}
