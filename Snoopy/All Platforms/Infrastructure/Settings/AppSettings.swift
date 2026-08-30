//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import KeyValueStore

// MARK: - AppSettings

/// A container for application-wide user settings.
///
/// `AppSettings` provides observable properties that represent user preferences
/// and persists them using an underlying key–value store.
/// It is designed to be injected into SwiftUI views and other components
/// that depend on reactive settings.
///
@Observable @MainActor public final class AppSettings {

    // MARK: Key

    /// The keys used to store and retrieve settings from the underlying store.
    public enum Key: String {
        /// The preferred color scheme for the app.
        case colorScheme

        /// Which speech recognition model to transcribe with.
        case asrBackend
    }

    // MARK: Properties

    /// The app's current color scheme preference.
    public var colorScheme: AppColorScheme {
        didSet {
            store.save(colorScheme, for: .colorScheme)
        }
    }
    
    /// The speech recognition model new transcriptions will use.
    ///
    /// Defaults to KB-Whisper Large: on real Swedish meeting audio it is the
    /// only option that reliably produces readable text. Parakeet remains
    /// selectable for its speed.
    public var asrBackend: ASRBackendKind {
        didSet {
            store.save(asrBackend.rawValue, for: .asrBackend)
        }
    }

    // MARK: Setup

    /// The key–value store that backs this settings container.
    @ObservationIgnored
    private let store: AnyKeyValueStore<AppSettings.Key>

    /// Creates a new instance of `AppSettings`.
    ///
    /// - Parameter store: The store used to persist values. If `nil`,
    ///   defaults to a `UserDefaults`-backed store.
    ///
    public init(store: AnyKeyValueStore<AppSettings.Key>? = nil) {
        self.store = store ?? .defaultStore
        colorScheme = self.store.load(.colorScheme, default: .system)
        
        asrBackend = ASRBackendKind(
            rawValue: self.store.load(.asrBackend, default: ASRBackendKind.default.rawValue)
        ) ?? .default
    }
}
