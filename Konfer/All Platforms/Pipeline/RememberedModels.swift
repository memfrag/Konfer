//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// The model last used for each language that has a choice of them, so the
/// Transcribe sheet opens on it next time.
///
/// Kept as one short string, `"danish=roest-whisper"`, because it lives in user
/// defaults beside the sheet. Anything it can't read, or a model the language
/// no longer offers, is simply not remembered — the language's default takes
/// over rather than a model that can't transcribe it.
nonisolated struct RememberedModels: Equatable, Sendable {

    private(set) var models: [MeetingLanguage: ASRBackendKind] = [:]

    init(_ stored: String) {
        for entry in stored.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let language = MeetingLanguage(rawValue: parts[0]),
                  let model = ASRBackendKind(rawValue: parts[1]),
                  ASRBackendKind.choices(for: language).contains(model)
            else { continue }
            models[language] = model
        }
    }

    /// The model to start on for a language: the one last used, or its
    /// default.
    func model(for language: MeetingLanguage) -> ASRBackendKind {
        models[language] ?? ASRBackendKind(transcribing: language)
    }

    mutating func remember(_ model: ASRBackendKind, for language: MeetingLanguage) {
        guard ASRBackendKind.choices(for: language).contains(model) else { return }
        models[language] = model
    }

    /// Sorted, so the same memory is always written the same way.
    var stored: String {
        models
            .map { "\($0.key.rawValue)=\($0.value.rawValue)" }
            .sorted()
            .joined(separator: ";")
    }
}
