# Attributions

Snoopy itself is released under the BSD Zero Clause License — see [LICENSE](LICENSE).
0BSD asks nothing of you: no attribution, no notice, no conditions.

The components below are a different matter. They are other people's work, and
some of their licences do ask for attribution, which is what this file is for.

Two of them are worth calling out before the lists:

- **The speaker diarization models are CC BY 4.0**, which *requires*
  attribution. Anyone shipping a build of Snoopy has to carry that credit.
- **The models are downloaded at runtime, not bundled.** A copy of Snoopy's
  source contains none of them; the first transcription in a given language
  fetches what it needs. They are listed here because a running Snoopy uses
  them.

---

## Speech and speaker models

| Model | Used for | Licence | Published by |
|---|---|---|---|
| [Apple `SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber) | English, German, Spanish, French, Italian, Portuguese | Part of macOS | Apple Inc. |
| [KB-Whisper Large](https://huggingface.co/KBLab/kb-whisper-large) | Swedish | Apache-2.0 | KBLab, National Library of Sweden |
| [Whisper large-v3](https://huggingface.co/openai/whisper-large-v3) | Danish, Dutch, Polish | Apache-2.0 | OpenAI |
| [pyannote speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) | Every transcription | **CC BY 4.0** | Hervé Bredin and the pyannote authors |

Apple's models are installed by macOS itself, per locale, and are governed by
the macOS software licence rather than anything Snoopy can grant.

KB-Whisper is a fine-tune of OpenAI's Whisper large-v3, trained on more than
50,000 hours of Swedish.

### The conversions Snoopy actually downloads

None of the Whisper models are usable on the Neural Engine as published, so
Snoopy fetches CoreML conversions of them:

| Repository | Contains | Licence |
|---|---|---|
| [mickekringai/kb-whisper-coreml](https://huggingface.co/mickekringai/kb-whisper-coreml) | KB-Whisper, converted for WhisperKit | Apache-2.0 |
| [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | Whisper large-v3, converted for WhisperKit | MIT |
| [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml) | pyannote community-1, converted for FluidAudio | **CC BY 4.0** |

---

## Swift packages

### BSD Zero Clause — Apparata AB

| Package | Version | Copyright |
|---|---|---|
| [AppRouting](https://github.com/apparata/AppRouting) | 0.9.2 | © 2025 Apparata AB |
| [AttributionsUI](https://github.com/apparata/AttributionsUI) | 1.1.1 | © 2023 Apparata AB |
| [BinaryDataKit](https://github.com/apparata/BinaryDataKit) | 1.0.7 | © 2019–2025 Apparata AB |
| [CGMath](https://github.com/apparata/CGMath) | 1.1.2 | © 2024 Apparata AB |
| [CollectionKit](https://github.com/apparata/CollectionKit) | 1.1.1 | © 2025 Apparata AB |
| [Constructs](https://github.com/apparata/Constructs) | 2.1.2 | © 2025 Apparata AB |
| [KeyValueStore](https://github.com/apparata/KeyValueStore) | 1.0.2 | © 2025 Apparata AB |
| [MarkdownUI](https://github.com/apparata/MarkdownUI) | 0.9.1 | © 2024 Apparata AB |
| [Markin](https://github.com/apparata/Markin) | 1.0.1 | © 2018 Apparata AB |
| [MathKit](https://github.com/apparata/MathKit) | 2.2.2 | Apparata AB |
| [SensibleStyling](https://github.com/apparata/SensibleStyling) | 0.2.1 | © 2021 Apparata AB |
| [SettingsUI](https://github.com/apparata/SettingsUI) | 1.1.5 | © 2025 Apparata AB |
| [SwiftUIToolbox](https://github.com/apparata/SwiftUIToolbox) | 2.0.0 | © 2025 Apparata AB |
| [SystemKit](https://github.com/apparata/SystemKit) | 1.8.0 | © 2019 Apparata AB |
| [TextToolbox](https://github.com/apparata/TextToolbox) | 1.4.0 | © 2025 Apparata AB |
| [URLToolbox](https://github.com/apparata/URLToolbox) | 1.3.1 | © 2025 Apparata AB |
| [UserDefaultsUI](https://github.com/apparata/UserDefaultsUI) | 1.0.1 | © 2023 Apparata AB |

### MIT

| Package | Version | Copyright |
|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) (`argmax-oss-swift`) | 1.1.0 | © 2024 Argmax, Inc. |
| [MessagePackKit](https://github.com/apparata/MessagePackKit) | 1.4.1 | © 2019 Apparata AB |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.1 | © 2006–2013 Andy Matuschak; © 2009–2013 Elgato Systems GmbH; © 2011–2014 Kornel Lesiński; © 2015–2017 Mayur Pawashe; and others |

### Apache License 2.0

| Package | Version | Copyright |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | 0.15.6 | Fluid Inference |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 | © 2020 Apple Inc. and the Swift project authors |

### Licence not stated

| Package | Version | Note |
|---|---|---|
| [Zipcode](https://github.com/apparata/Zipcode) | 1.0.1 | Resolved as a dependency, but the repository carries no licence file. |

---

## Code bundled inside FluidAudio

FluidAudio vendors these rather than depending on them, so they ship inside
Snoopy along with it.

| Component | Licence | Copyright |
|---|---|---|
| [fastcluster](https://github.com/fastcluster/fastcluster) | BSD-2-Clause | © 2011 Daniel Müllner; changes from v1.1.24 © Google Inc. |
| [VBx](https://github.com/BUTSpeechFIT/VBx) | Apache-2.0 | BUT Speech@FIT, Brno University of Technology |
| [text-processing-rs](https://github.com/FluidInference/text-processing-rs) | Apache-2.0 | Fluid Inference |

Snoopy's diarization is the pyannote community-1 pipeline reimplemented in
Swift by FluidAudio: pyannote segmentation, speaker embeddings, and
agglomerative clustering by way of fastcluster, with VBx behind the clustering
refinement.

---

## How this list was produced

The Swift package licences and copyright lines were read from the `LICENSE`
files in the resolved checkouts of the versions pinned in
`Package.resolved` — not from memory or from the packages' READMEs. The model
licences were read from the Hugging Face API's `license` field for each
repository. If you change a dependency version, re-read rather than assume:
`ATTRIBUTIONS.md` is only as true as its last check.
