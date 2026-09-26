# Attributions

Konfer itself is released under the BSD Zero Clause License — see [LICENSE](LICENSE).
0BSD asks nothing of you: no attribution, no notice, no conditions.

The components below are a different matter. They are other people's work, and
some of their licences do ask for attribution, which is what this file is for.

The same list is shown inside the app, from the About window, and is built in
`OpenSourceAttributions.swift`. Change one and change the other — with the exception of Apple's
own frameworks, which appear here but not there, because macOS is not software
included in this product.

Two of them are worth calling out before the lists:

- **The speaker diarization models are CC BY 4.0**, which *requires*
  attribution. Anyone shipping a build of Konfer has to carry that credit.
- **The models are downloaded at runtime, not bundled.** A copy of Konfer's
  source contains none of them; the first transcription in a given language
  fetches what it needs. They are listed here because a running Konfer uses
  them.

---

## Speech and speaker models

| Model | Used for | Licence | Published by |
|---|---|---|---|
| [Apple `SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber) | English, German, Spanish, French, Italian, Portuguese | Part of macOS | Apple Inc. |
| [KB-Whisper Large](https://huggingface.co/KBLab/kb-whisper-large) | Swedish | Apache-2.0 | KBLab, National Library of Sweden |
| [Røst v3](https://huggingface.co/CoRal-project/roest-v3-whisper-1.5b) | Danish | **Røst Model License** (AI Pubs Open RAIL-M, with use restrictions) | The CoRal project; licensed by Alvenir ApS |
| [Whisper large-v3](https://huggingface.co/openai/whisper-large-v3) | Dutch, Polish, and Danish when chosen | Apache-2.0 | OpenAI |
| [pyannote speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) | Every transcription | **CC BY 4.0** | Hervé Bredin and the pyannote authors; speaker embedding by WeSpeaker; PLDA parameters by BUT Speech@FIT |

Apple's models are installed by macOS itself, per locale, and are governed by
the macOS software licence rather than anything Konfer can grant.

KB-Whisper is a fine-tune of OpenAI's Whisper large-v3, trained on more than
50,000 hours of Swedish. Røst v3 is one too, trained on read and
conversational Danish by the CoRal project.

### The conversions Konfer actually downloads

None of the Whisper models are usable on the Neural Engine as published, so
Konfer fetches CoreML conversions of them:

| Repository | Contains | Licence |
|---|---|---|
| [mickekringai/kb-whisper-coreml](https://huggingface.co/mickekringai/kb-whisper-coreml) | KB-Whisper, converted for WhisperKit | Apache-2.0 |
| [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | Whisper large-v3, converted for WhisperKit | MIT |
| [kramerthomas/roest-v3-whisper-1.5b-coreml](https://huggingface.co/kramerthomas/roest-v3-whisper-1.5b-coreml) | Røst v3, converted for WhisperKit at 8 bits; pinned to commit `3e9222be` | Røst Model License |
| [FluidInference/speaker-diarization-coreml](https://huggingface.co/FluidInference/speaker-diarization-coreml) | pyannote community-1, converted for FluidAudio | **CC BY 4.0** (for the Community-1 files) |

The diarization conversion's
[NOTICE.md](https://huggingface.co/FluidInference/speaker-diarization-coreml/blob/main/NOTICE.md)
asks that the credit name pyannote, WeSpeaker, BUT Speech@FIT and Fluid
Inference, link the licence, say that the files are modified Core ML
conversions, and keep the citations from its README — so the in-app entry
does all of that. Its CC BY scope covers only the Community-1 files
(`Segmentation`, `FBank`, `Embedding`, `PLDA`, `PldaRho` and the two PLDA
JSON files), which are the only ones FluidAudio's offline diarizer loads; the
older `wespeaker` and `pyannote_segmentation` files in the same repository are
excluded from it, and Konfer never downloads them.

Røst's licence is not permissive in the way the others are. It is Alvenir
ApS's, governed by Danish law, built on the AI Pubs Open RAIL-M licence, and
it carries **use restrictions** that anyone distributing the model must pass
on to the people using it — so the in-app entry summarises them rather than
only linking. Among them: no using the model to break the law, to harm or
discriminate, to impersonate people or synthesise a person's voice, to detect
or infer a person's identity or personal characteristics, or to spread
machine-generated content without saying it is machine-generated. Konfer only
transcribes with it; recognising voices is done by the diarization embeddings
above, never by Røst. The full terms are in the
[conversion's LICENSE](https://huggingface.co/kramerthomas/roest-v3-whisper-1.5b-coreml/blob/main/LICENSE).

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

### The Unlicense

| Package | Version | Copyright |
|---|---|---|
| [Zipcode](https://github.com/apparata/Zipcode) | 1.0.1 | Released into the public domain by Apparata AB |

---

## Code bundled inside those packages

These are vendored rather than depended on, so they ship inside Konfer along
with the package that carries them.

| Component | Inside | Licence | Copyright |
|---|---|---|---|
| [fastcluster](https://github.com/fastcluster/fastcluster) | FluidAudio | BSD-2-Clause | © 2011 Daniel Müllner; changes from v1.1.24 © Google Inc. |
| [VBx](https://github.com/BUTSpeechFIT/VBx) | FluidAudio | Apache-2.0 | BUT Speech@FIT, Brno University of Technology |
| [text-processing-rs](https://github.com/FluidInference/text-processing-rs) | FluidAudio | Apache-2.0 | Fluid Inference |
| [NeMo Text Processing](https://github.com/NVIDIA/NeMo-text-processing) | FluidAudio, compiled into text-processing-rs | Apache-2.0 | © NVIDIA Corporation & Affiliates |
| [rustfst](https://github.com/Garvys/rustfst) | FluidAudio, compiled into text-processing-rs | MIT OR Apache-2.0 | © Alexandre Caulier and the rustfst contributors |
| [flate2](https://github.com/rust-lang/flate2-rs) | FluidAudio, compiled into text-processing-rs | MIT OR Apache-2.0 | © Alex Crichton and the flate2 contributors |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | WhisperKit | Apache-2.0 | © 2022 Hugging Face SAS, modified by Argmax, Inc. |
| [bsdiff](http://www.daemonology.net/bsdiff/) 4.3 | Sparkle | BSD-2-Clause | © 2003–2005 Colin Percival |
| [sais-lite](https://sites.google.com/site/yuta256/sais) | Sparkle | MIT | © 2008–2010 Yuta Mori |
| [Ed25519](https://github.com/orlp/ed25519) | Sparkle | zlib | © 2015 Orson Peters |
| `SUSignatureVerifier.m` | Sparkle | BSD-2-Clause | © 2011 Mark Hamlin |

text-processing-rs reaches FluidAudio as a prebuilt framework, so what is
compiled into it appears in no checkout; FluidAudio lists it in
`ThirdPartyLicenses/NemoTextProcessing-LICENSE.md`, along with smaller MIT and
Apache-2.0 crates (nom, miniz_oxide, bitflags, anyhow and others) that
rustfst and flate2 pull in. Sparkle's four are in the EXTERNAL LICENSES part
of its own `LICENSE`.

Konfer's diarization is the pyannote community-1 pipeline reimplemented in
Swift by FluidAudio: pyannote segmentation, speaker embeddings, and
agglomerative clustering by way of fastcluster, with VBx behind the clustering
refinement.

---

## How this list was produced

The Swift package licences and copyright lines were read from the licence
files in the resolved checkouts of the versions pinned in `Package.resolved` —
not from memory or from the packages' READMEs. The model licences were read
from the Hugging Face API's `license` field for each repository.

Two traps worth knowing, because this file fell into both on the first pass:

- **The file is not always called `LICENSE`.** Zipcode's is `UNLICENSE`, which a
  search for `LICENSE*` misses entirely — and a missing licence file reads as
  "no licence" when it actually means the opposite, a public domain dedication.
- **A package's own licence is not the whole story.** WhisperKit and FluidAudio
  both vendor other people's code and declare it in a separate `NOTICES` or
  `ThirdPartyLicenses` file, which is where the table above comes from. Sparkle
  does the same inside its `LICENSE`, below the MIT text, which is how its four
  entries were missed the first time.
- **A model's licence can change under you.** The diarization conversion
  started asking for a fuller credit in September 2026, with no change to
  anything Konfer pins. Re-read the model cards too, not just the packages.

If you change a dependency version, re-read rather than assume: this file is
only as true as its last check.
