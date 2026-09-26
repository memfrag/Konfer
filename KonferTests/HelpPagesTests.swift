//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Testing
import Foundation
import MarkdownUI
@testable import Konfer

/// The help pages are Markdown files, and everything that can go wrong with
/// one goes wrong silently: a renamed file is a blank page, a mistyped link
/// opens nothing, a mistyped `<view>` tag is a missing button. So every page
/// is opened here, in the bundle the app actually ships.
@MainActor
struct HelpPagesTests {

    // MARK: - Helpers

    private func markdown(_ topic: HelpTopic) throws -> String {
        try #require(topic.markdown(), "\(topic.resourceName).md is not in the app bundle")
    }

    /// Every link in a page, wherever it sits — paragraph, list or table.
    private func links(in markdown: String) throws -> [URL] {
        let string = try AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .full)
        )
        return string.runs[\.link].compactMap { link, _ in link }
    }

    // MARK: - Tests

    @Test("Every help topic has a page in the app bundle", arguments: HelpTopic.allCases)
    func everyTopicHasAPage(topic: HelpTopic) throws {
        let text = try markdown(topic)
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("Every page opens with its own title, so the sidebar and the page agree", arguments: HelpTopic.allCases)
    func pageTitleMatchesSidebar(topic: HelpTopic) throws {
        let firstLine = try markdown(topic).split(separator: "\n").first.map(String.init)
        #expect(firstLine == "# \(topic.title)")
    }

    @Test("Every page parses into blocks MarkdownUI can draw", arguments: HelpTopic.allCases)
    func everyPageParses(topic: HelpTopic) throws {
        let document = try MarkdownDocument(try markdown(topic))
        #expect(document.blocks.count > 1)
    }

    @Test("A link to another help page names a page that exists", arguments: HelpTopic.allCases)
    func helpLinksResolve(topic: HelpTopic) throws {
        for url in try links(in: try markdown(topic)) where url.scheme == HelpTopic.linkScheme {
            #expect(HelpTopic(link: url) != nil, "\(topic.resourceName).md links to \(url)")
        }
    }

    @Test("Every button written into a page is one the help window can draw", arguments: HelpTopic.allCases)
    func customViewsAreKnown(topic: HelpTopic) throws {
        let document = try MarkdownDocument(try markdown(topic))
        for case .customView(let view) in document.blocks {
            #expect(
                HelpAction.kind(tag: view.tag, parameters: view.parameters) != nil,
                "\(topic.resourceName).md has <view tag=\"\(view.tag)\" \(view.parameters)>"
            )
        }
    }

    /// Without this the test above passes vacuously: a `<view>` tag MarkdownUI
    /// fails to recognise comes back as a paragraph of literal text, which
    /// has no custom views to check.
    @Test("Every <view> tag written into a page is parsed as a button", arguments: HelpTopic.allCases)
    func customViewsAreParsed(topic: HelpTopic) throws {
        let text = try markdown(topic)
        let written = text.components(separatedBy: "<view ").count - 1
        let parsed = try MarkdownDocument(text).blocks.count {
            if case .customView = $0 { true } else { false }
        }
        #expect(parsed == written)
    }

    @Test("A help link reads the same with or without slashes")
    func linkForms() {
        #expect(HelpTopic(link: URL(string: "konfer-help:recording")!) == .recording)
        #expect(HelpTopic(link: URL(string: "konfer-help://getting-started")!) == .gettingStarted)
    }

    @Test("Web links and unknown pages are not help links")
    func notHelpLinks() {
        #expect(HelpTopic(link: URL(string: "https://example.com/recording")!) == nil)
        #expect(HelpTopic(link: URL(string: "konfer-help:no-such-page")!) == nil)
    }

    @Test("A button may only open the windows help is allowed to open")
    func unknownWindowIsRefused() {
        #expect(HelpAction.kind(tag: "open-window", parameters: ["window": "help", "label": "Help"]) == nil)
        #expect(HelpAction.kind(tag: "open-window", parameters: ["window": "people"]) == nil)
        #expect(
            HelpAction.kind(tag: "open-window", parameters: ["window": "people", "label": "Open People"])
                == .openWindow(id: "people", label: "Open People")
        )
    }
}
