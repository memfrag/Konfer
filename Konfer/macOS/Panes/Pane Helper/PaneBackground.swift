//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

struct PaneBackground: View {
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if colorScheme == .dark {
            Color(.clear)
                .edgesIgnoringSafeArea(.all)
        } else {
            Color.white
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    PaneBackground()
}
