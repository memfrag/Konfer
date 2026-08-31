//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

struct GeneralSettingsTab: View {

    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        @Bindable var appSettings = appSettings

        Form {
            Section {
                Picker("Appearance:", selection: $appSettings.colorScheme) {
                    Text("System").tag(AppColorScheme.system)
                    Text("Light").tag(AppColorScheme.light)
                    Text("Dark").tag(AppColorScheme.dark)
                }
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
#endif
