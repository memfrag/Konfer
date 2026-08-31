//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// Stable colours for speakers, so a person keeps the same colour as you scroll.
enum SpeakerPalette {

    private static let colors: [Color] = [
        .blue, .orange, .purple, .green, .pink, .teal, .indigo, .brown
    ]

    /// Colour for a speaker, by position in the meeting's roster.
    static func color(at index: Int) -> Color {
        guard index >= 0 else { return .gray }
        return colors[index % colors.count]
    }

    static func color(for speakerId: String, in meeting: Meeting) -> Color {
        guard speakerId != SpeakerLabel.unknownID,
              let index = meeting.speakers.firstIndex(where: { $0.id == speakerId })
        else { return .gray }
        return color(at: index)
    }
}
