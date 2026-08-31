//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation
import SwiftUI
import AppRouting

/// An application-wide environment container.
///
/// This type centralizes access to shared app state and dependencies that are
/// safe to read from anywhere in the app, such as `AppSettings`. Prefer
/// injecting instances via SwiftUI's `@Environment`.
///
/// Use ``AppEnvironment/default`` for the process-global environment that is
/// created lazily at launch based on build configuration and the
/// `APP_ENVIRONMENT` process environment variable.
///
/// - Important: Avoid creating your own instances unless you are writing
///   previews or tests.
///
public final class AppEnvironment {

    // MARK: - Properties

    /// Application settings used throughout the app.
    public let appSettings: AppSettings

    /// Engineering mode
    internal let engineeringMode: EngineeringMode

    /// The library of transcribed meetings.
    internal let meetingStore: MeetingStore

    /// People Konfer has learned to recognise across meetings.
    internal let speakerStore: SpeakerStore

    /// Runs recordings through diarization and speech recognition.
    internal let pipeline: TranscriptionPipeline

    /// Downloads the models. Shared, because the downloads window, Settings and
    /// the first-run screen all drive the same queue.
    internal let downloads: ModelDownloadQueue

    // MARK: - Init

    /// Creates an environment with the provided dependencies.
    ///
    /// - Note: Use ``live()``/``mock()`` rather than this initializer.
    ///
    internal init(
        appSettings: AppSettings,
        engineeringMode: EngineeringMode,
        meetingStore: MeetingStore,
        speakerStore: SpeakerStore,
        pipeline: TranscriptionPipeline,
        downloads: ModelDownloadQueue
    ) {
        self.appSettings = appSettings
        self.engineeringMode = engineeringMode
        self.meetingStore = meetingStore
        self.speakerStore = speakerStore
        self.pipeline = pipeline
        self.downloads = downloads
    }
}
