//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The People window, opened from the toolbar above the sidebar and from
/// Window ▸ People.
///
/// A single `Window` rather than a `WindowGroup`: there is one roster, and a
/// second copy of it open beside the first would only be a second place to
/// rename the same person.
struct PeopleWindow: Scene {

    static let windowID = "people"

    var body: some Scene {
        Window("People", id: Self.windowID) {
            // The environment is injected here, inside the window — a Scene
            // itself has no access to it.
            PeopleView()
                .appEnvironment(.default)
        }
        .defaultSize(width: 720, height: 480)
        .defaultPosition(.center)
    }
}
