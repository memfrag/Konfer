//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import AppRouting

// MARK: - View Extension

extension View {

    /// Applies the shared application environment to the view.
    ///
    /// - Parameter appEnvironment: The `AppEnvironment` containing shared
    ///   objects such as the meeting library and the transcription pipeline.
    /// - Returns: A modified view with the application environment applied.
    ///
    func appEnvironment(_ appEnvironment: AppEnvironment) -> some View {
        self
            .environment(appEnvironment.appSettings)
            .environment(appEnvironment.engineeringMode)
            .environment(appEnvironment.meetingStore)
            .environment(appEnvironment.speakerStore)
            .environment(appEnvironment.pipeline)
            .environment(appEnvironment.downloads)
    }

    #if DEBUG
    func previewEnvironment() -> some View {
        let appEnvironment = AppEnvironment.mock()
        return self
            .environment(appEnvironment.appSettings)
            .environment(appEnvironment.engineeringMode)
            .environment(appEnvironment.meetingStore)
            .environment(appEnvironment.speakerStore)
            .environment(appEnvironment.pipeline)
            .environment(appEnvironment.downloads)
    }
    #endif
}
