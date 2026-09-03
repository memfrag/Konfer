//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

/// The no-selection state, which doubles as the app's front door.
struct EmptyPane: View {

    var onImport: (() -> Void)?

    var body: some View {
        Pane {
            VStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 4) {
                    Text("No recording selected")
                        .font(.title3)
                    Text("Drop a recording here to transcribe it, or a transcript to import it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let onImport {
                    Button("Choose Recording…", action: onImport)
                }
            }
            .padding(40)
        }
    }
}

#Preview {
    EmptyPane()
}
