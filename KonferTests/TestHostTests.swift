//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// Every test run launches the whole app as its host, and the app reads and
/// rewrites the library on launch. These pin that a test run is recognised
/// as one and kept off the user's own data — see `TestHost` for the run that
/// wasn't.
@MainActor
struct TestHostTests {

    @Test("The app hosting the tests knows it is only hosting tests")
    func recognisesTheTestHost() {
        #expect(TestHost.isHostingTests)
    }

    @Test("The app hosting the tests reads a throwaway library, not the user's")
    func hostUsesAThrowawayLibrary() {
        let library = AppEnvironment.default.meetingStore.url(of: .root).standardizedFileURL
        #expect(library != LibraryLocation.meetingsDirectory.standardizedFileURL)
        #expect(library.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path))
    }
}
