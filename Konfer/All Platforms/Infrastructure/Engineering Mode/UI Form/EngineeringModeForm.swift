//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import OSLog
import SettingsUI
import UserDefaultsUI

struct EngineeringModeForm: View {

    enum Destination {
        case userDefaultsBrowser
    }

    var body: some View {
        Form(content: {

            // MARK: - Info

            Section {
                LabelSetting(
                    "Version",
                    systemIcon: "info.circle.fill",
                    info: "\(AppVersion().description)"
                )
            }

            // MARK: - User Defaults Browser

            Section("User Defaults") {
                PushSetting(
                    "Browse User Defaults",
                    systemIcon: "switch.2",
                    value: Destination.userDefaultsBrowser
                )
            }

            // MARK: - App Paths

#if targetEnvironment(simulator)
            Section("App Paths") {
                ButtonSetting(
                    "Copy App Bundle Path",
                    systemIcon: "folder.fill"
                ) {
                    let path = Bundle.main.bundleURL.path
                    Logger.engineeringMode.trace("👷‍♀️ \(path)")
                    UIPasteboard.general.string = path
                }

                ButtonSetting(
                    "Copy App Container Path",
                    systemIcon: "folder.fill"
                ) {
                    let path = NSHomeDirectory()
                    Logger.engineeringMode.trace("👷‍♀️ \(path)")
                    UIPasteboard.general.string = path
                }
            }
#endif
        })
        .navigationDestination(for: Destination.self) { value in
            switch value {
            case .userDefaultsBrowser:
                UserDefaultsBrowser(hidePrefixes: ["pizza.martin."])
            }
        }
    }
}

// MARK: Preview

#Preview {
    EngineeringModeForm()
}
