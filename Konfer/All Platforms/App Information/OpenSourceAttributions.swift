//
//  Copyright © 2026 Martin Johannesson. All rights reserved.
//

import AttributionsUI

/// Everything Konfer includes or downloads that someone else wrote, as shown
/// in the Attributions window.
///
/// Kept in step with ATTRIBUTIONS.md, which records where each of these was
/// read from. Years and holders come from the licence file in the resolved
/// checkout; where a licence states neither, the entry says so rather than
/// inventing one.
enum OpenSourceAttributions {

    static let header = "The following software may be included in this product."

    // In three parts because a single literal this long is more than the
    // type checker will take on.
    static let entries: [Attributions.Entry] = packages + bundled + models

    // MARK: Swift packages

    private static let packages: [Attributions.Entry] = [
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
    ]

    // MARK: Vendored inside those packages

    private static let bundled: [Attributions.Entry] = [
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
        // Compiled into text-processing-rs, which FluidAudio links as a
        // prebuilt framework — so they ship even though no source of theirs
        // is in any checkout. Listed in FluidAudio's
        // ThirdPartyLicenses/NemoTextProcessing-LICENSE.md.
        ("NeMo Text Processing (in FluidAudio)", .custom(
            name: "Apache License 2.0",
            spdxID: "Apache-2.0",
            text: "Text normalization grammars derived from NVIDIA NeMo Text "
                + "Processing, Copyright (c) NVIDIA CORPORATION & AFFILIATES, "
                + "used under the Apache License 2.0. "
                + "See https://github.com/NVIDIA/NeMo-text-processing"
        )),
        ("rustfst (in FluidAudio)", .custom(
            name: "MIT License or Apache License 2.0",
            spdxID: "MIT OR Apache-2.0",
            text: "Copyright (c) Alexandre Caulier and the rustfst contributors, "
                + "used under the MIT License. "
                + "See https://github.com/Garvys/rustfst"
        )),
        ("flate2 (in FluidAudio)", .custom(
            name: "MIT License or Apache License 2.0",
            spdxID: "MIT OR Apache-2.0",
            text: "Copyright (c) Alex Crichton and the flate2 contributors, used "
                + "under the MIT License. Together with the smaller MIT and "
                + "Apache-2.0 crates it and rustfst depend on, such as nom, "
                + "miniz_oxide, bitflags and anyhow. "
                + "See https://github.com/rust-lang/flate2-rs"
        )),
        ("swift-transformers (in WhisperKit)", .apache2(
            year: "2022", holder: "Hugging Face SAS, modified by Argmax, Inc."
        )),
        // Named in the EXTERNAL LICENSES part of Sparkle's own licence file.
        // The two BSD licences require their notice in binary distributions.
        ("bsdiff (in Sparkle)", .bsd2Clause(year: "2003-2005", holder: "Colin Percival")),
        ("sais-lite (in Sparkle)", .mit(year: "2008-2010", holder: "Yuta Mori")),
        ("Ed25519 (in Sparkle)", .zlib(year: "2015", holder: "Orson Peters")),
        ("SUSignatureVerifier (in Sparkle)", .bsd2Clause(year: "2011", holder: "Mark Hamlin")),
    ]

    // MARK: Speech and speaker models

    private static let models: [Attributions.Entry] = [
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
        ("Pianissimo model", pianissimo),
        ("pyannote speaker diarization models", diarization)
    ]

    // CC BY requires the credit, a link to the licence, and a statement of
    // what was changed — the same three things the release notes carry.
    private static let pianissimo = OpenSourceLicense(
        name: "Creative Commons Attribution 4.0 International",
        spdxID: "CC-BY-4.0",
        text: [
            "Klang Pianissimo, a Swedish speech recognition model by Klang AI "
                + "AB, fine-tuned from NVIDIA Parakeet TDT 0.6B v3. Used under "
                + "the Creative Commons Attribution 4.0 International license, "
                + "https://creativecommons.org/licenses/by/4.0/ . "
                + "See https://huggingface.co/KlangAI/pianissimo-sv",
            "Konfer downloads a modified version: its own Core ML conversion, "
                + "with the encoder's weights quantized to 8 bits and its local "
                + "attention expressed as a band mask over full attention, "
                + "published under the same licence at "
                + "https://github.com/memfrag/Konfer/releases/tag/pianissimo-sv-120s-1",
        ]
    )

    // CC BY requires this credit rather than merely inviting it. Worded
    // after the conversion's NOTICE.md, which asks for all four parties,
    // the licence link, a statement that the files are modified, and the
    // citations its README carries.
    private static let diarization = OpenSourceLicense(
        name: "Creative Commons Attribution 4.0 International",
        spdxID: "CC-BY-4.0",
        text: diarizationCredit
    )

    private static let diarizationCredit: [String] = [
        "Speaker diarization models from pyannote "
            + "speaker-diarization-community-1, by Hervé Bredin and the "
            + "pyannote authors: speaker segmentation by pyannote, speaker "
            + "embedding by WeSpeaker, and PLDA parameters by BUT "
            + "Speech@FIT, Brno University of Technology. Used under the "
            + "Creative Commons Attribution 4.0 International license, "
            + "https://creativecommons.org/licenses/by/4.0/",
        "Konfer downloads modified versions of them: Core ML "
            + "conversions by Fluid Inference, with fixed input shapes "
            + "and mixed-precision storage, published at "
            + "https://huggingface.co/FluidInference/speaker-diarization-coreml "
            + "under the same licence.",
        "Plaquet, A. and Bredin, H. Powerset multi-class cross entropy "
            + "loss for neural speaker diarization. Proc. INTERSPEECH "
            + "2023.",
        "Wang, H., Liang, C., Wang, S., Chen, Z., Zhang, B., Xiang, X., "
            + "Deng, Y. and Qian, Y. Wespeaker: A research and production "
            + "oriented speaker embedding learning toolkit. ICASSP 2023.",
        "Landini, F., Profant, J., Diez, M. and Burget, L. Bayesian HMM "
            + "clustering of x-vector sequences (VBx) in speaker "
            + "diarization: theory, implementation and analysis on "
            + "standard tasks. Computer Speech & Language, 2022."
    ]
}
