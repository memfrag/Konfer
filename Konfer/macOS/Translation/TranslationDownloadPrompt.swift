//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import Translation

/// A view with nothing in it, whose only job is to ask macOS for a language
/// pair.
///
/// The headless `TranslationSession` that does all of Konfer's translating
/// reports `canRequestDownloads == false`, so the one thing it cannot do is
/// fetch the pair it is missing. Only a session vended by `.translationTask`
/// can, and only by calling `prepareTranslation()`, which puts up the system's
/// own download sheet. Hence an empty view, parked inside ``TranslateSheet``.
///
/// This is the same arrangement ``AppleSpeechBackend`` already lives with for
/// speech locales: the models belong to macOS, and Konfer's job is to ask at
/// the right moment rather than to manage them.
struct TranslationDownloadPrompt: View {

    /// Set to start a download; cleared when it finishes.
    let pair: TranslationPair?

    let onFinished: () -> Void

    @State private var configuration: TranslationSession.Configuration?

    /// Bumped when a download attempt ends, so the callback can be made from
    /// the main actor rather than from inside the task.
    @State private var attempts = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            // `@Sendable`, and so nonisolated, on purpose: the app builds with
            // default-`MainActor` isolation, and `TranslationSession` is not
            // `Sendable`, so a main-actor closure here would be receiving it
            // across an isolation boundary.
            .translationTask(configuration) { @Sendable session in
                try? await session.prepareTranslation()
                await MainActor.run { attempts += 1 }
            }
            .onChange(of: attempts) { _, _ in onFinished() }
            .onChange(of: pair, initial: true) { _, pair in
                guard let pair else {
                    configuration = nil
                    return
                }
                // A fresh configuration each time, so declining a download and
                // asking again puts the sheet back up rather than resolving
                // instantly against the one already answered.
                configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: pair.source.code),
                    target: Locale.Language(identifier: pair.target.code)
                )
            }
    }
}
