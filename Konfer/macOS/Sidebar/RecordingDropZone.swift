//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// A place at the foot of the sidebar to drop a recording or voice memo.
///
/// It exists because the empty space below the sidebar's rows can't take a
/// drop. The list there is an outline view, which proposes a drop onto the
/// list itself as child index -1, and SwiftUI hands that to a `ForEach`'s
/// drop handler as an index and crashes (HomogeneousCollection.swift: "index
/// -1 out of bounds"). So the drop target lives in the bar below the list
/// instead, where it is an ordinary SwiftUI view — and, being visible, says
/// that dropping is possible at all.
struct RecordingDropZone: View {

    /// Returns whether the drop was taken.
    let onDrop: ([LibraryDrop]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus")
                .imageScale(.large)
            Text("Drop a recording or voice memo here to transcribe it")
                .font(.caption)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargeted ? [] : [5, 4])
                )
        )
        .contentShape(Rectangle())
        .dropDestination(for: LibraryDrop.self) { drops, _ in
            onDrop(drops)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isTargeted = targeted }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Drop a recording or voice memo to transcribe it")
    }
}
