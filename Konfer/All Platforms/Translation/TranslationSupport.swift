//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// A direction of translation between two of Konfer's languages.
nonisolated struct TranslationPair: Hashable, Sendable {
    let source: MeetingLanguage
    let target: MeetingLanguage
}

/// Which of Konfer's languages macOS will translate between.
///
/// Deliberately a table rather than a probe. `LanguageAvailability` answers one
/// pair per `await`, and the Translate sheet needs to know about nine before it
/// can draw its picker — so the pairs macOS refuses outright are recorded here
/// and the live check runs only for the pair actually chosen.
///
/// Measured across all 72 ordered pairs of Konfer's ten languages: 68 are
/// offered, Polish needs downloading against every one of them, and four do not
/// exist at all — Swedish and Danish against Polish, in both directions. Both
/// of those reach English perfectly well, which is exactly the temptation this
/// refuses: a hop through English would return a fluent Polish sentence that is
/// a translation of a translation, with nothing on screen to say which half of
/// it to distrust. A refusal is legible; a double translation is not.
///
/// Pessimistic if Apple adds a pair later. The cost of being stale is a
/// language Konfer declines to offer, never a translation it gets wrong — the
/// live check still runs before any job starts.
nonisolated enum TranslationSupport {

    /// Pairs macOS reports as `unsupported`, in both directions.
    static let unavailablePairs: Set<TranslationPair> = {
        let refused: [(MeetingLanguage, MeetingLanguage)] = [
            (.swedish, .polish),
            (.danish, .polish)
        ]
        return Set(refused.flatMap {
            [TranslationPair(source: $0.0, target: $0.1),
             TranslationPair(source: $0.1, target: $0.0)]
        })
    }()

    static func isKnownUnavailable(from source: MeetingLanguage, to target: MeetingLanguage) -> Bool {
        unavailablePairs.contains(TranslationPair(source: source, target: target))
    }

    /// The languages a meeting in `source` can be translated into, in the
    /// picker's own order. A language is never offered as a translation of
    /// itself; the pairs macOS refuses are still listed, so the sheet can say
    /// why rather than quietly leaving a gap where Polish should be.
    static func targets(for source: MeetingLanguage) -> [MeetingLanguage] {
        MeetingLanguage.allCases.filter { $0 != source }
    }
}
