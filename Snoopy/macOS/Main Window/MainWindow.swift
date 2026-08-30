//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    var body: some Scene {

        WindowGroup {
            Sidebar()
                .frame(minWidth: 720, minHeight: 460)
                .appEnvironment(.default)
                .terminatesAppWhenClosed()
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            SidebarCommands()
            ExportCommands()
            HelpCommands()

            // Snoopy has no notion of an empty new document — a meeting only
            // exists once a recording has been transcribed.
            CommandGroup(replacing: .newItem, addition: { })
        }
    }
}
