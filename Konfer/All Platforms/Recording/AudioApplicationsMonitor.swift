//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import CoreAudio
import Foundation

/// Watches for changes to the set of applications whose audio can be tapped.
///
/// Without this the recorder's list is a snapshot taken when its window opens,
/// which is the moment *before* the user starts the call they mean to record:
/// the app they want appears a second later and the list never says so.
///
/// Two different events change that set, and Core Audio reports only one of
/// them:
///
/// - An app that has never played audio has no process object at all, and
///   gains one when it starts. `kAudioHardwarePropertyProcessObjectList` is a
///   notifying property, so this arrives at once.
/// - An app that already has a process object — a browser that played
///   something earlier, a call client sitting muted — keeps it and merely
///   flips `kAudioProcessPropertyIsRunningOutput`, which is what decides
///   membership of the list. **That property does not notify.** Measured on
///   macOS 26: a listener on it registers successfully, the value provably
///   changes underneath, and the block is never called.
///
/// So the listener covers the first case instantly and a slow poll covers the
/// second. Listing every process that merely *has* a process object would
/// avoid the poll — it is the notifying condition — but that set is 20 entries
/// of `loginwindow`, `PowerChime` and `universalaccessd` on an idle Mac, which
/// is not a picker anybody can use.
///
/// Callbacks are delivered on the main queue, which keeps the whole class on
/// the main actor and lets it hold its registration in a plain property rather
/// than behind a lock.
///
@MainActor
final class AudioApplicationsMonitor {

    /// How often the set is re-examined in the absence of a notification.
    ///
    /// Two seconds because `isRunningOutput` lags the audio by about that much
    /// on its own — measured going false roughly 2.3s after playback stopped —
    /// so a tighter loop would spend cycles to report the same value.
    static let pollInterval: Duration = .seconds(2)

    private var onChange: (@MainActor () -> Void)?

    /// Kept because removing a Core Audio listener needs the very block that
    /// was added, not an equivalent one.
    private var listListener: AudioObjectPropertyListenerBlock?

    private var pollTask: Task<Void, Never>?

    private static var processListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: - Lifecycle

    /// Starts reporting changes. Calling this twice replaces the first handler
    /// rather than adding a second set of listeners.
    ///
    /// There is no `deinit` cleanup: removing a listener touches main-actor
    /// state, which a `deinit` cannot reach. ``stop()`` is the contract, and
    /// the recorder window calls it when it closes.
    /// - Parameter pollInterval: Injected only so tests need not wait seconds
    ///   for the backstop to prove it fires.
    func start(
        pollInterval: Duration = AudioApplicationsMonitor.pollInterval,
        onChange: @escaping @MainActor () -> Void
    ) {
        stop()
        self.onChange = onChange

        var address = Self.processListAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, listener
        ) == noErr {
            listListener = listener
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: pollInterval)
                guard !Task.isCancelled else { return }
                self?.onChange?()
            }
        }
    }

    func stop() {
        if let listListener {
            var address = Self.processListAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, listListener
            )
        }
        listListener = nil

        pollTask?.cancel()
        pollTask = nil

        onChange = nil
    }
}
