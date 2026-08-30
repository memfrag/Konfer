//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A peak level bar for one side of a recording.
///
/// Its job is to be checked *before* committing to an hour: a silent track is
/// only discoverable afterwards, when it is too late to do anything about it.
struct LevelMeter: View {

    let label: String
    let level: Float
    let color: Color

    /// False when this side isn't being recorded at all, which is different
    /// from being recorded and silent.
    var isActive: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(displayLevel))
                }
            }
            .frame(height: 6)

            Text(isActive ? caption : "off")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
        .opacity(isActive ? 1 : 0.4)
    }

    /// Levels are compressed for display: linear amplitude spends most of its
    /// range looking like nothing at all for ordinary speech.
    private var displayLevel: Float {
        guard isActive, level > 0 else { return 0 }
        let decibels = 20 * log10(max(level, 0.000_1))
        return min(max((decibels + 60) / 60, 0), 1)
    }

    private var caption: String {
        guard level > 0.000_1 else { return "—" }
        return String(format: "%.0f dB", 20 * log10(level))
    }
}

#Preview {
    VStack {
        LevelMeter(label: "Microphone", level: 0.4, color: .blue)
        LevelMeter(label: "Call audio", level: 0.05, color: .orange)
        LevelMeter(label: "Call audio", level: 0, color: .orange, isActive: false)
    }
    .padding()
    .frame(width: 360)
}
