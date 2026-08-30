//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// What the sidebar can have selected.
///
/// The boilerplate's fixed enum of panes doesn't fit an app whose navigation is
/// mostly a list of documents, so meetings carry their id and the roster is the
/// one fixed destination.
enum SidebarSelection: Hashable {
    case meeting(UUID)
    case speakers
}
