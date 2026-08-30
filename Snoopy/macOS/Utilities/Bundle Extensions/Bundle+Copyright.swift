//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

extension Bundle {
    
    var copyright: String? {
        func string(for key: String) -> String? {
            object(forInfoDictionaryKey: key) as? String
        }
        return string(for: "NSHumanReadableCopyright")
    }
}
