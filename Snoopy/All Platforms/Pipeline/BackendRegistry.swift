//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Vends transcription backends, keeping each one loaded once it's been used.
///
/// Models are expensive to load — minutes on a first compile — so switching
/// back and forth in Settings shouldn't pay that cost twice. Backends stay
/// resident until `unloadAll()`, which the Models settings tab calls before
/// deleting anything from disk.
///
actor BackendRegistry {

    private var backends: [ASRBackendKind: any TranscriptionBackend] = [:]

    func backend(for kind: ASRBackendKind) -> any TranscriptionBackend {
        if let existing = backends[kind] { return existing }

        let backend: any TranscriptionBackend = switch kind {
        case .automatic, .appleSpeech: AppleSpeechBackend()
        case .kbWhisperSmall: WhisperKitBackend(variant: .small)
        case .kbWhisperLarge: WhisperKitBackend(variant: .large)
        }
        backends[kind] = backend
        return backend
    }

    func unloadAll() async {
        for backend in backends.values {
            await backend.unload()
        }
        backends.removeAll()
    }
}
