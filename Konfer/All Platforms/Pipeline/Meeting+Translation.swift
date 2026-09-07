//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

// MARK: - TranscriptRendering

/// Which of a meeting's two texts a view or an export is showing.
///
/// The transcript is never both at once. A line of Swedish under a line of
/// English reads as a language course rather than a record of a meeting, and
/// doubles the height of every turn in a pane whose whole job is to be
/// skimmed.
nonisolated enum TranscriptRendering: String, Equatable, Sendable {
    case original
    case translated
}

// MARK: - Reading a translation

nonisolated extension Meeting {

    /// The language this meeting has been translated into, if any.
    var translationTarget: MeetingLanguage? { translation?.target }

    /// This turn in the translation language, or nil if it has none.
    func translatedText(for utterance: Utterance) -> String? {
        translation?.text(for: utterance.id)
    }

    /// What a view or an export should print for this turn.
    ///
    /// Falls back to the original rather than to nothing. A turn loses its
    /// translation the moment its text is edited, and a reading view with
    /// holes in it is unreadable — the original is the honest thing to show,
    /// and both the pane and the Markdown export say when they are showing it.
    func text(for utterance: Utterance, rendering: TranscriptRendering) -> String {
        guard rendering == .translated else { return utterance.text }
        return translatedText(for: utterance) ?? utterance.text
    }

    /// The kept turns with nothing to show in the translation language — what
    /// "Translate the Rest" sends after an edit or a cancelled run.
    var untranslatedKeptUtterances: [Utterance] {
        keptUtterances.filter {
            translatedText(for: $0) == nil
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
