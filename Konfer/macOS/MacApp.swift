//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import AppDesign
import Sparkle

@main
struct MacApp: App {

    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Before any store reads from disk: the folder moved when the app was
        // renamed. See `LibraryMigration`.
        LibraryMigration.migrateIfNeeded()
        AppDesign.apply()
    }

    var body: some Scene {
        MainWindow(updater: updaterController.updater)
        RecorderWindow()
        ModelDownloadsWindow()
        WelcomeWindow()
        SettingsWindow()
        AboutWindow(developedBy: "Martin Johannesson",
                    attributionsWindowID: AttributionsWindow.windowID)
        // Kept in step with ATTRIBUTIONS.md, which records where each of these
        // was read from. Years and holders come from the licence file in the
        // resolved checkout; where a licence states neither, the entry says so
        // rather than inventing one.
        AttributionsWindow([

            // MARK: Swift packages

            ("AppRouting", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("AttributionsUI", .bsd0Clause(year: "2023", holder: "Apparata AB")),
            ("BinaryDataKit", .bsd0Clause(year: "2019-2025", holder: "Apparata AB")),
            ("CGMath", .bsd0Clause(year: "2024", holder: "Apparata AB")),
            ("CollectionKit", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Constructs", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("KeyValueStore", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("MarkdownUI", .bsd0Clause(year: "2024", holder: "Apparata AB")),
            ("Markin", .bsd0Clause(year: "2018", holder: "Apparata AB")),
            ("MathKit", .custom(
                name: "BSD Zero Clause License",
                spdxID: "0BSD",
                text: "Published at https://github.com/apparata/MathKit under the "
                    + "BSD Zero Clause License. The licence file names no year or "
                    + "holder; the source files carry Bontouch AB copyright notices."
            )),
            ("MessagePackKit", .mit(year: "2019", holder: "Apparata AB")),
            ("SensibleStyling", .bsd0Clause(year: "2021", holder: "Apparata AB")),
            ("SettingsUI", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("SwiftUIToolbox", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("SystemKit", .bsd0Clause(year: "2019", holder: "Apparata AB")),
            ("TextToolbox", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("URLToolbox", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("UserDefaultsUI", .bsd0Clause(year: "2023", holder: "Apparata AB")),
            ("Zipcode", .custom(
                name: "The Unlicense",
                spdxID: "Unlicense",
                text: "This is free and unencumbered software released into the "
                    + "public domain by Apparata AB. See https://unlicense.org/"
            )),

            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al.")),
            ("WhisperKit", .mit(year: "2024", holder: "Argmax, Inc.")),
            ("FluidAudio", .apache2(year: "2025", holder: "Fluid Inference")),
            ("swift-argument-parser", .apache2(
                year: "2020", holder: "Apple Inc. and the Swift project authors"
            )),

            // MARK: Vendored inside those packages

            ("fastcluster (in FluidAudio)", .bsd2Clause(
                year: "2011", holder: "Daniel Müllner, and Google Inc. for later changes"
            )),
            ("VBx (in FluidAudio)", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Speaker clustering from the VBx project by BUT Speech@FIT, "
                    + "Brno University of Technology, used under the Apache License "
                    + "2.0. See https://github.com/BUTSpeechFIT/VBx"
            )),
            ("text-processing-rs (in FluidAudio)", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Text normalization by Fluid Inference, used under the Apache "
                    + "License 2.0. "
                    + "See https://github.com/FluidInference/text-processing-rs"
            )),
            ("swift-transformers (in WhisperKit)", .apache2(
                year: "2022", holder: "Hugging Face SAS, modified by Argmax, Inc."
            )),

            // MARK: Speech and speaker models

            ("KB-Whisper model", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Swedish speech recognition model by KBLab at the National "
                    + "Library of Sweden, a fine-tune of OpenAI's Whisper large-v3, "
                    + "used under the Apache License 2.0. Downloaded as the CoreML "
                    + "conversion at huggingface.co/mickekringai/kb-whisper-coreml, "
                    + "also Apache 2.0. "
                    + "See https://huggingface.co/KBLab/kb-whisper-large"
            )),
            ("Whisper large-v3 model", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Speech recognition model by OpenAI, used under the Apache "
                    + "License 2.0. Downloaded as the CoreML conversion at "
                    + "huggingface.co/argmaxinc/whisperkit-coreml, which is MIT "
                    + "licensed. "
                    + "See https://huggingface.co/openai/whisper-large-v3"
            )),
            // CC BY requires this credit rather than merely inviting it.
            ("pyannote speaker diarization models", .custom(
                name: "Creative Commons Attribution 4.0 International",
                spdxID: "CC-BY-4.0",
                text: "Speaker diarization models (speaker-diarization-community-1) "
                    + "by Hervé Bredin and the pyannote authors, used under the "
                    + "Creative Commons Attribution 4.0 International license. "
                    + "Downloaded as the CoreML conversion at "
                    + "huggingface.co/FluidInference/speaker-diarization-coreml, "
                    + "under the same licence. "
                    + "See https://creativecommons.org/licenses/by/4.0/"
            ))
        ], header: "The following software may be included in this product.")
        HelpWindow()
    }
}
