//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
@testable import Konfer

/// The monitor exists because the recorder's application list was a snapshot
/// taken before the user started the call they meant to record. What matters is
/// that it reports at all: `kAudioProcessPropertyIsRunningOutput` decides
/// membership of that list and is not a property Core Audio notifies on, so the
/// poll is the only thing standing between a correct list and the old snapshot.
///
/// Driven at a millisecond interval rather than the shipping two seconds, and
/// touching no audio — Core Audio's process list is always readable.
@MainActor
struct AudioApplicationsMonitorTests {

    private let interval = Duration.milliseconds(50)

    @Test("Changes are reported without waiting for a notification that never comes")
    func pollReportsChanges() async throws {
        let monitor = AudioApplicationsMonitor()
        defer { monitor.stop() }

        var reports = 0
        monitor.start(pollInterval: interval) { reports += 1 }

        try await Task.sleep(for: interval * 6)

        #expect(reports >= 1)
    }

    @Test("A stopped monitor goes quiet")
    func stopEndsReports() async throws {
        let monitor = AudioApplicationsMonitor()

        var reports = 0
        monitor.start(pollInterval: interval) { reports += 1 }
        try await Task.sleep(for: interval * 6)

        let whenStopped = reports
        monitor.stop()
        try await Task.sleep(for: interval * 6)

        #expect(whenStopped >= 1, "the monitor never reported anything to begin with")
        #expect(reports == whenStopped)
    }

    @Test("Starting twice replaces the handler rather than reporting to both")
    func restartReplacesHandler() async throws {
        let monitor = AudioApplicationsMonitor()
        defer { monitor.stop() }

        var first = 0
        var second = 0
        monitor.start(pollInterval: interval) { first += 1 }
        try await Task.sleep(for: interval * 4)

        monitor.start(pollInterval: interval) { second += 1 }
        let whenReplaced = first
        try await Task.sleep(for: interval * 6)

        #expect(second >= 1)
        #expect(first == whenReplaced, "the replaced handler is still being called")
    }
}
