//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

public struct HelpWindow: Scene {

    public static let windowID = "help"
            
    public var body: some Scene {
        Window("Help", id: Self.windowID) {
            VStack {
                Text("No help available.")
            }
            .frame(minWidth: 500, minHeight: 350)
        }
        .commandsRemoved() // Don't show window in Windows menu
        .defaultPosition(.center)
        .defaultSize(width: 500, height: 350)
        .windowResizability(.contentMinSize)
    }
}
