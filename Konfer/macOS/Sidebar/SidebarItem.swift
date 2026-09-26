//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import CoreTransferable
import UniformTypeIdentifiers

/// A meeting or folder being dragged within the sidebar.
///
/// Its own type rather than a file URL, although both are files on disk:
/// the window already accepts dropped URLs as recordings to transcribe, and a
/// meeting dropped a few points wide of a folder would otherwise be offered up
/// for transcription.
nonisolated enum SidebarItem: Codable, Hashable, Transferable {
    case meeting(UUID)
    case folder([String])

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .konferLibraryItem)
    }
}

extension UTType {
    /// Declared in Info.plist, which is what makes it a type the system will
    /// carry through a drag.
    nonisolated static let konferLibraryItem = UTType(exportedAs: "pizza.martin.Konfer.library-item")
}
