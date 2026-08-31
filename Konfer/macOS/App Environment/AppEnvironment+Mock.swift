//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import AppRouting

extension AppEnvironment {

    // MARK: - Mock AppEnvironment

    #if DEBUG
    /// Builds a mock environment configured for development and preview usage.
    ///
    /// The stores are pointed at a throwaway directory so previews never touch
    /// the real library.
    ///
    /// Available only in `DEBUG` builds.
    ///
    internal static func mock() -> AppEnvironment {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KonferPreview-\(UUID().uuidString)")

        let meetingStore = MeetingStore(directory: directory)
        let speakerStore = SpeakerStore(directory: directory)

        return AppEnvironment(
            appSettings: AppSettings.mock(),
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
    #endif
}
