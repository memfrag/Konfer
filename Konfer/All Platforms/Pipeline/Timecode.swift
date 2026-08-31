//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Timestamp formatting shared by the transcript view and the exporters.
nonisolated enum Timecode {

    /// `12:34` under an hour, `1:02:03` beyond it.
    static func short(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Always `00:12:34`, for export where alignment matters.
    static func padded(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(
            format: "%02d:%02d:%02d",
            total / 3600, (total % 3600) / 60, total % 60
        )
    }
}
