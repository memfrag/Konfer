//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import MarkdownUI

/// The pages down the side, the chosen one beside them.
struct HelpView: View {

    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            if let selection {
                HelpPage(topic: selection)
                    // A fresh page per topic, so it opens scrolled to the top.
                    .id(selection)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .environment(\.openURL, OpenURLAction { url in
            guard let topic = HelpTopic(link: url) else {
                return .systemAction
            }
            selection = topic
            return .handled
        })
    }
}

// MARK: - Page

private struct HelpPage: View {

    let topic: HelpTopic

    /// Parsed once per page rather than on every refresh, as MarkdownUI asks.
    @State private var document: MarkdownDocument?

    init(topic: HelpTopic) {
        self.topic = topic
        _document = State(initialValue: topic.markdown().flatMap {
            try? MarkdownDocument($0)
        })
    }

    var body: some View {
        if let document {
            ScrollView {
                Markdown(document, lazy: false, customView: { customView in
                    HelpAction(customView)
                })
                .markdownStyle(.help)
                .textSelection(.enabled)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(topic.title)
        } else {
            ContentUnavailableView(
                "Page Missing",
                systemImage: "questionmark.text.page",
                description: Text("“\(topic.title)” isn’t in this copy of Konfer.")
            )
        }
    }
}

// MARK: - Style

private extension MarkdownStyle {

    /// MarkdownUI's defaults are sized for a phone — a `.largeTitle` heading and
    /// generous paragraph gaps. This is tighter, to read like a Mac help book.
    static let help = MarkdownStyle(
        header1: .init(padding: .init(top: 0, bottom: 8), font: .title.bold(), color: .primary),
        header2: .init(padding: .init(top: 18, bottom: 2), font: .title2.bold(), color: .primary),
        header3: .init(padding: .init(top: 12, bottom: 0), font: .headline, color: .primary),
        paragraph: .init(padding: .init(top: 6, bottom: 6), font: .body, color: .primary),
        image: .init(padding: .init(top: 8, bottom: 8), cornerRadius: 8, bundle: .main),
        unorderedList: .init(
            padding: .init(top: 4, bottom: 6),
            element: .init(bullet: "•", bulletPadding: 4, bulletFont: .body, indentation: 16, font: .body)
        ),
        orderedList: .init(
            padding: .init(top: 4, bottom: 6),
            element: .init(bulletPadding: 4, bulletFont: .body.monospacedDigit(), indentation: 16, font: .body)
        ),
        blockquote: .init(
            padding: .init(top: 6, bottom: 8),
            indentation: 12,
            lineDecoration: .init(color: .accentColor, width: 3, padding: 10),
            font: .body,
            textColor: .secondary
        ),
        table: .init(
            padding: .init(top: 6, bottom: 8),
            headerFont: .headline,
            headerColor: .primary,
            cellFont: .body,
            cellColor: .primary
        )
    )
}
