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
        SettingsWindow()
        AboutWindow(developedBy: "Martin Johannesson",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow([
            ("CGMath", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("MathKit", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al.")),
            ("FluidAudio", .apache2(year: "2025", holder: "Fluid Inference")),
            ("VBx (in FluidAudio)", .apache2(year: "2021", holder: "Brno University of Technology")),
            ("fastcluster (in FluidAudio)", .bsd2Clause(year: "2011", holder: "Daniel Müllner")),
            ("Parakeet TDT 0.6B v3 model", .custom(
                name: "Creative Commons Attribution 4.0 International",
                spdxID: "CC-BY-4.0",
                text: "Speech recognition model © 2025 NVIDIA Corporation, used "
                    + "under the Creative Commons Attribution 4.0 International "
                    + "license. See https://creativecommons.org/licenses/by/4.0/"
            )),
            ("pyannote speaker diarization models", .mit(year: "2024", holder: "Hervé Bredin et al."))
        ], header: "The following software may be included in this product.")
        HelpWindow()
    }
}
