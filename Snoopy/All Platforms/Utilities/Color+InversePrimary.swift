//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox

extension Color {
    static var inversePrimary: Color {
        #if os(macOS)
        Color(NSUIColor(name: nil, dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                .white
            } else {
                .black
            }
        }))
        #else
        Color(NSUIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .black : .white
        })
        #endif
    }
}
