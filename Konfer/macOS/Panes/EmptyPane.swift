//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The no-selection state, which doubles as the app's front door.
///
/// So it offers both ways a meeting gets into Konfer, not only the one that
/// starts from a file: someone who has never recorded with it has no reason
/// to guess that it records, and a Choose Recording button on its own reads
/// as though it only transcribes what you already have.
struct EmptyPane: View {

    /// Set where the pane is the front door, which is also what offers the
    /// Recorder. Unset where it stands in for a meeting that has gone.
    var onImport: (() -> Void)?

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Pane {
            VStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    Text("No recording selected")
                        .font(.title3)
                    Text("Record a meeting, or drop a recording here to transcribe it. \nOr drop a transcript file here to import it.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        // Narrow enough to break into two even lines rather
                        // than one long one and a stranded last word.
                        .frame(maxWidth: 380)
                }

                if let onImport {
                    HStack(spacing: 10) {
                        Button("Record a Meeting…") {
                            openWindow(id: RecorderWindow.windowID)
                        }
                        Button("Choose Recording…", action: onImport)
                    }
                }
            }
            .padding(40)
        }
    }
}

#Preview {
    EmptyPane()
}
