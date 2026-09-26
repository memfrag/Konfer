//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import MarkdownUI

/// A button in the middle of a help page, written in its Markdown as
///
///     <view tag="open-window" window="model-downloads" label="Open Model Downloads"/>
///     <view tag="open-settings" label="Open Settings…"/>
///
/// so a page that says where something is can also take the reader there.
/// Anything unrecognised draws nothing; `HelpPagesTests` checks every tag in
/// every page against ``HelpAction/Kind``, so a typo fails a test instead of
/// silently losing a button.
struct HelpAction: View {

    nonisolated enum Kind: Equatable, Sendable {
        case openWindow(id: String, label: String)
        case openSettings(label: String)
    }

    /// The windows a page may open. Not every scene: help opening help, or
    /// the welcome window a second time, would only be confusing.
    static let openableWindows: Set<String> = [
        RecorderWindow.windowID,
        ModelDownloadsWindow.windowID,
        PeopleWindow.windowID,
    ]

    /// What a custom view in a page asks for, or nil when it isn't one of ours.
    static func kind(tag: String, parameters: [String: String]) -> Kind? {
        switch tag {
        case "open-window":
            guard let id = parameters["window"], openableWindows.contains(id),
                  let label = parameters["label"] else {
                return nil
            }
            return .openWindow(id: id, label: label)
        case "open-settings":
            return .openSettings(label: parameters["label"] ?? "Open Settings…")
        default:
            return nil
        }
    }

    @Environment(\.openWindow) private var openWindow

    private let kind: Kind?

    init(_ customView: MarkdownBlock.CustomView) {
        kind = Self.kind(tag: customView.tag, parameters: customView.parameters)
    }

    var body: some View {
        Group {
            switch kind {
            case .openWindow(let id, let label):
                Button(label) {
                    openWindow(id: id)
                }
            case .openSettings(let label):
                SettingsLink {
                    Text(label)
                }
            case nil:
                EmptyView()
            }
        }
        .padding(.vertical, 6)
    }
}
