//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// One page of the help window, in the order the sidebar lists them.
///
/// Each page is a Markdown file in `Help Pages/`, bundled as a resource. The
/// synchronized folder copies it into the bundle's flat `Resources/`, which is
/// why every file carries the `help-` prefix: nothing else in the app may
/// share its name, or the build fails with two files claiming one path.
nonisolated enum HelpTopic: String, CaseIterable, Identifiable, Sendable {

    case gettingStarted = "getting-started"
    case recording
    case transcribing
    case reading
    case editing
    case people
    case translation
    case exporting
    case models
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .recording: "Recording a Meeting"
        case .transcribing: "Transcribing a File"
        case .reading: "Reading and Playback"
        case .editing: "Editing a Transcript"
        case .people: "People"
        case .translation: "Translation"
        case .exporting: "Exporting"
        case .models: "Models and Storage"
        case .troubleshooting: "Troubleshooting"
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: "star"
        case .recording: "record.circle"
        case .transcribing: "waveform"
        case .reading: "play.circle"
        case .editing: "pencil"
        case .people: "person.2"
        case .translation: "translate"
        case .exporting: "square.and.arrow.up"
        case .models: "internaldrive"
        case .troubleshooting: "wrench.and.screwdriver"
        }
    }

    var resourceName: String { "help-\(rawValue)" }

    /// The page's Markdown, or nil when the file isn't in the bundle.
    ///
    /// Nil should never reach a user: `HelpPagesTests` opens every page.
    func markdown(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md") else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Links between pages

extension HelpTopic {

    /// Pages link to each other as `konfer-help:recording`. A custom scheme,
    /// because MarkdownUI hands every link to `openURL` and has no anchors of
    /// its own; the help window catches this one and changes page instead.
    static let linkScheme = "konfer-help"

    /// The page a help link points at, or nil for any other URL.
    init?(link url: URL) {
        guard url.scheme == Self.linkScheme else {
            return nil
        }
        // `konfer-help:recording` has the page as its opaque path;
        // `konfer-help://recording` has it as the host. Accept both.
        let name = url.host() ?? url.absoluteString.dropFirst(Self.linkScheme.count + 1)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.init(rawValue: name)
    }
}
