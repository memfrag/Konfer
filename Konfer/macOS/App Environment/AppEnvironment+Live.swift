//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import AppRouting

extension AppEnvironment {

    // MARK: - Live AppEnvironment

    /// Builds a live environment configured for production behavior.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with live dependencies.
    ///
    internal static func live() -> AppEnvironment {
        let meetingStore = MeetingStore()
        let speakerStore = SpeakerStore()

        return AppEnvironment(
            appSettings: AppSettings(),
            engineeringMode: EngineeringMode.shared,
            meetingStore: meetingStore,
            speakerStore: speakerStore,
            pipeline: TranscriptionPipeline(
                diarizer: DiarizationService(),
                meetingStore: meetingStore,
                speakerStore: speakerStore
            ),
            downloads: ModelDownloadQueue()
        )
    }
}
