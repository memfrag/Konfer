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
        AttributionsWindow([
            ("CGMath", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("MathKit", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al.")),
            ("WhisperKit", .mit(year: "2024", holder: "Argmax, Inc.")),
            ("FluidAudio", .apache2(year: "2025", holder: "Fluid Inference")),
            ("VBx (in FluidAudio)", .apache2(year: "2021", holder: "Brno University of Technology")),
            ("fastcluster (in FluidAudio)", .bsd2Clause(
                year: "2011", holder: "Daniel Müllner, and Google Inc. for later changes"
            )),
            ("KB-Whisper model", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Swedish speech recognition model by KBLab at the National "
                    + "Library of Sweden, a fine-tune of OpenAI's Whisper "
                    + "large-v3, used under the Apache License 2.0. "
                    + "See https://huggingface.co/KBLab/kb-whisper-large"
            )),
            ("Whisper large-v3 model", .custom(
                name: "Apache License 2.0",
                spdxID: "Apache-2.0",
                text: "Speech recognition model by OpenAI, used under the "
                    + "Apache License 2.0. "
                    + "See https://huggingface.co/openai/whisper-large-v3"
            )),
            // CC BY requires this credit rather than merely inviting it.
            ("pyannote speaker diarization models", .custom(
                name: "Creative Commons Attribution 4.0 International",
                spdxID: "CC-BY-4.0",
                text: "Speaker diarization models (speaker-diarization-community-1) "
                    + "by Hervé Bredin and the pyannote authors, used under the "
                    + "Creative Commons Attribution 4.0 International license. "
                    + "See https://creativecommons.org/licenses/by/4.0/"
            ))
        ], header: "The following software may be included in this product.")
        HelpWindow()
    }
}
