//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI

extension View {
    public func smoothCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(
            RoundedRectangle(
                cornerRadius: radius,
                style: .continuous
            )
        )
    }
}
