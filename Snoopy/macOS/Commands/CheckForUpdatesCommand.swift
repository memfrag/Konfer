//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Combine
import SwiftUI
import Sparkle

/// Sparkle's "Check for Updates…" item, disabled while Sparkle is busy.
struct CheckForUpdatesCommand: Commands {

    let updater: SPUUpdater

    @StateObject private var model: UpdaterAvailability

    init(updater: SPUUpdater) {
        self.updater = updater
        _model = StateObject(wrappedValue: UpdaterAvailability(updater: updater))
    }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!model.canCheckForUpdates)
        }
    }
}

/// Mirrors Sparkle's `canCheckForUpdates`, which is KVO rather than published.
private final class UpdaterAvailability: ObservableObject {

    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
