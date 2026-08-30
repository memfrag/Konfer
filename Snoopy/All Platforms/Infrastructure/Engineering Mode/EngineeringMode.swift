//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import KeyValueStore

@Observable final class EngineeringMode {
    
    private enum Key: String {
        case exampleSetting
    }

    var exampleSetting: Int {
        didSet {
            store.save(exampleSetting, for: .exampleSetting)
        }
    }

    private(set) var isEnabled: Bool = false
    
    private let store = UserDefaultsStore(keyedBy: Key.self, prefixedBy: "EngineeringMode")

    #if !os(macOS)    
    private let appStateObserver = AppStateObserver()
    #endif

    private init() {
        exampleSetting = store.load(.exampleSetting, default: 1337)
        updateEnabledStatus()
    }
    
    // MARK: Enabled Status Changes

    #if !os(macOS)
    private func observeEnabledStatusChanges() {
        appStateObserver.appDidBecomeActive = { [weak self] in
            self?.updateEnabledStatus()
        }
    }
    #endif
    
    private func updateEnabledStatus() {
        #if DEBUG
        isEnabled = true
        #else
        isEnabled = false
        #endif
    }
}

// MARK: - Singleton

extension EngineeringMode {
    /// When possible, use `@Environment(EngineeringMode.self)` rather than
    /// accessing the `shared` property directly.
    static let shared = EngineeringMode()
}
