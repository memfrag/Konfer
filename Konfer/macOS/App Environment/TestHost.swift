//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Whether this process is only hosting the unit tests.
///
/// The test target is hosted in Konfer.app, so every test run launches the
/// whole app, and the app on launch reads — and since folders, rewrites —
/// the library in Application Support. On 2026-09-26 a test run renamed the
/// author's real transcripts from `<UUID>.json` to their titles before the
/// build that does so had ever been opened on purpose. Nothing was lost, but
/// a test run has no business touching anyone's data, so a hosting app runs
/// on a throwaway library, skips the one-time migration, and shows no
/// first-run window.
///
/// Read from the environment `xcodebuild` launches the host with, which is in
/// place before `MacApp.init` runs — unlike the test bundle, which is loaded
/// later. By presence rather than value: measured under `xcodebuild test`
/// with swift-testing, `XCTestConfigurationFilePath` is set but empty, so a
/// check for a non-empty path would miss every run.
///
/// The integration tests that deliberately use the real library
/// (`KONFER_LIBRARY=real`) build their own stores and are unaffected.
nonisolated enum TestHost {

    static let isHostingTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return ["XCTestSessionIdentifier", "XCTestBundlePath", "XCTestConfigurationFilePath"]
            .contains { environment[$0] != nil }
    }()
}
