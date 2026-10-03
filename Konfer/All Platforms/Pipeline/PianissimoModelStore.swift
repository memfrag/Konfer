//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import Foundation

/// Where Konfer's own CoreML conversion of Pianissimo lives.
///
/// Klang publishes Pianissimo only as NeMo, ONNX and MLX. The community CoreML
/// conversions all fix the encoder at FluidAudio's 15-second window, and on a
/// real meeting that window cost the model whole phrases its authors' 2-minute
/// chunks keep — "där vi bara gick runt bordet idag", "En kille har byggt".
/// This conversion takes 120 seconds at a time instead, the length Klang's own
/// MLX script uses, with the checkpoint's local attention (±256 frames)
/// reproduced as a band mask over full attention: the same function to 2e-6,
/// but plain masked attention that CoreML can convert.
///
/// Made by `scripts/pianissimo-coreml/convert.sh` from `KlangAI/pianissimo-sv`
/// at revision `8f1f6d8f…`, which records its settings in `conversion.json`.
/// Not yet hosted anywhere, so for now `convert.sh --install` puts it here.
///
/// Lives beside KB-Whisper under ``KBWhisperModelStore/directory``, so
/// Settings ▸ Models measures and deletes it with the rest.
///
nonisolated enum PianissimoModelStore {

    static let components = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecisionv3.mlmodelc",
        "parakeet_vocab.json",
    ]

    static var directory: URL {
        KBWhisperModelStore.directory.appendingPathComponent("pianissimo-sv-120s", isDirectory: true)
    }

    static func url(for component: String) -> URL {
        directory.appendingPathComponent(component)
    }

    static var isInstalled: Bool {
        components.allSatisfy { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    static func remove() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
