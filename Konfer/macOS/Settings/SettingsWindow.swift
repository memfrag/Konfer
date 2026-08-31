//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Show settings window by using a SettingsLink SwiftUI view.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case general
        case transcription
        case models
    }

    var body: some Scene {
        Settings {
            tabs
        }
    }

    @ViewBuilder var tabs: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)

            TranscriptionSettingsTab()
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .tag(Tabs.transcription)

            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "internaldrive")
                }
                .tag(Tabs.models)
        }
        .frame(width: 520, height: 360)
        .appEnvironment(.default)
    }
}
