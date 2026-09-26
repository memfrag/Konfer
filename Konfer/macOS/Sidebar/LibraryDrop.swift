//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import CoreTransferable
import Foundation
import OSLog
import UniformTypeIdentifiers

/// Anything the window or a sidebar row takes by drag.
///
/// One type, because a view has one drop destination and a folder row has to
/// take all three: a meeting or folder being refiled, a recording from
/// Finder, and a recording from an app that only hands over copies.
///
/// The order of the representations is the point. A file on disk is matched
/// as a URL before anything else looks at it, so a recording dragged from
/// Finder is transcribed where it is — Konfer never copies audio it can
/// point at. Only what arrives without a URL falls through to the file
/// representation, and that is Voice Memos: a Mac Catalyst app, whose drags
/// are file promises — the file is written only when the receiver asks, to
/// a folder the receiver picks — so there is nothing to point at, and the
/// memo itself sits in Voice Memos' own protected storage.
nonisolated enum LibraryDrop: Transferable {

    /// A meeting or folder being moved within the sidebar.
    case item(SidebarItem)

    /// A file on disk: a recording to transcribe where it is, or a
    /// transcript to import.
    case file(URL)

    /// Audio another app would only hand over as a copy, waiting in a
    /// staging folder until it is either transcribed and given a home, or
    /// abandoned with the sheet.
    case copy(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (item: SidebarItem) in LibraryDrop.item(item) })
        ProxyRepresentation(importing: { (url: URL) in LibraryDrop.file(url) })
        FileRepresentation(importedContentType: .audiovisualContent) { received in
            .copy(try stage(received.file))
        }
    }

    /// Copies a received file somewhere it outlives the drop — the system
    /// deletes `received.file` as soon as the import returns — keeping its
    /// name, which for a Voice Memo is the memo's title.
    private static func stage(_ file: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Konfer Drops", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let staged = folder.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: staged)
        // Notice rather than info, which the system keeps: when a drag from
        // another app misbehaves, this is the line that says how far it got.
        logger.notice("Received a copy of \(file.lastPathComponent, privacy: .public)")
        return staged
    }

    static let logger = Logger(subsystem: "pizza.martin.Konfer", category: "Drop")
}
