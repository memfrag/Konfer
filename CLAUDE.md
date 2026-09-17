# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Konfer is a non-sandboxed macOS 26 SwiftUI app (Xcode 26, Swift 6.2) that records
and transcribes multi-speaker meetings entirely on device, in ten languages, and
translates them into each other. Everything runs locally except the one-time
model download.

Read `README.md` before changing the pipeline: it records the measurements behind
the non-obvious choices (why chunking is off, why slices are capped at 4, why the
language tag is pinned, why Canary and Parakeet were dropped). `Docs/BOILERPLATE.md`
describes the Apparata app template this started from — much of it no longer
matches the tree and it is not a guide to the current app.

## Build and test

```sh
xcodebuild -scheme "Konfer (Debug)" build
xcodebuild -scheme "Konfer (Debug)" test
```

Only `Konfer (Debug)` and `Konfer (Release)` are shared schemes; there is no plain
`Konfer` scheme. Tests use swift-testing (`@Test`/`#expect`), not XCTest.

A single suite or test:

```sh
xcodebuild test -scheme "Konfer (Debug)" -destination 'platform=macOS,arch=arm64' \
  -only-testing:KonferTests/SpeakerAlignerTests
```

Most tests are fixture-based — no models, no audio, no network. Three suites are
skipped unless you point them at a real recording, and they need the
`TEST_RUNNER_` prefix so `xcodebuild` forwards the variable to the test runner:

```sh
TEST_RUNNER_KONFER_AUDIO=/path/to/meeting.wav \
  xcodebuild test -scheme "Konfer (Debug)" -destination 'platform=macOS,arch=arm64' \
  -only-testing:KonferTests/PipelineIntegrationTests
```

`PipelineIntegrationTests` also reads `KONFER_BACKEND`, `KONFER_LANGUAGE`,
`KONFER_FAST`, `KONFER_SIDES=1` (treat the file as a Konfer recording with the
microphone and system audio on separate channels) and `KONFER_LIBRARY=real`; `RecordingSourceTests` needs
`KONFER_RECORD_APP`; `TranslationAvailabilityTests` needs
`KONFER_TRANSLATION=real` and Apple's language packs — it is the one suite that
checks the recorded pair table against what macOS actually reports. Keep test
parallelization off — two runner processes sharing one model cache corrupt each
other's download.

Runtime overrides for experiments: `KONFER_BACKEND` (forces a model, including
the otherwise unreachable `kb-whisper-small`), `KONFER_CHUNKING=vad`,
`KONFER_SLICES=1`,
`KONFER_WHISPER_VERBOSE=1`, `KONFER_VAD_PADDING`, `KONFER_RECORD_DIAGNOSTICS=1`,
`KONFER_TRANSLATE_CHUNK` (how many translated lines are written through at a
time), and `APP_ENVIRONMENT=mock` to launch against `AppEnvironment.mock()`.

`scripts/supported-locales.swift` (`swift scripts/supported-locales.swift`) lists
the locales Apple's `SpeechTranscriber` supports on this machine and which have
models installed — the check behind Konfer's "English via Apple, everything else
via KB-Whisper" split. Swedish is not among the 30.

There is no SwiftLint config in the repo, but the sources carry
`// swiftlint:disable:next` comments; keep them if you move that code.

## Release

`scripts/build-and-notarize.sh` archives the `Konfer (Release)` scheme, notarizes,
builds a DMG, signs for Sparkle, publishes a GitHub release and updates
`appcast.xml`.

```sh
./scripts/build-and-notarize.sh --version 1.2.0 --title "Konfer 1.2.0"
```

Both values are prompted for when omitted and a terminal is attached, and
required when one is not, so the same script serves a release cut by hand and
one cut by CI. It refuses up front — before archiving anything — if the
notarytool profile, `gh` auth or the Sparkle key is missing, or if the tag
already exists; each of those otherwise surfaces at the end, after the build.

The Sparkle key is checked by value, not merely for existence, and lives under
its own keychain account (`--account konfer`) because the default `ed25519`
account holds an older key belonging to something else. A key that isn't the
one in `SUPublicEDKey` signs updates that every installed copy refuses, and
`generate_appcast` only warns about that before writing the entry unsigned —
which is how 1.1.0 was published un-updatable and had to be re-signed by hand.
To set the key up on a new machine:

```sh
./Sparkle-tools/bin/generate_keys --account konfer -f <private-key-file>
```

The version lives in the build settings, not in `Info.plist`: the target sets
`GENERATE_INFOPLIST_FILE = YES`, so `CFBundleShortVersionString` and
`CFBundleVersion` are generated from `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.pbxproj`. Bump those; writing version keys
into `Konfer/macOS/Info.plist` has no effect.

## Architecture

**Layering.** `Konfer/All Platforms/` holds the model, pipeline, recording and
library layers; `Konfer/macOS/` holds SwiftUI views, windows and commands.
`Packages/AppDesign` is a local SPM package for colors, typography and assets.
Dependencies are mostly Apparata packages plus FluidAudio (diarization),
argmax-oss-swift/WhisperKit (Swedish ASR) and Sparkle (updates).

**Dependency injection.** `AppEnvironment` is the container, built by
`AppEnvironment.live()` / `.mock()` and chosen in `AppEnvironment+Default.swift`.
`View.appEnvironment(_:)` fans its members out into SwiftUI `@Environment`, so
views read `@Environment(MeetingStore.self)` etc. rather than the container.
`previewEnvironment()` is the preview/DEBUG equivalent.

**The three-stage pipeline** (`All Platforms/Pipeline/`). `TranscriptionPipeline`
is an `@Observable @MainActor` job queue that runs one recording at a time:
`AudioSourcePreparer` normalizes input → `DiarizationService` (FluidAudio) finds
who spoke when → a `TranscriptionBackend` from `BackendRegistry` produces word
timings → `SpeakerAligner` merges the two halves into `Utterance`s. The merge is
the piece nothing off the shelf provides, and it is the piece most worth testing.
Stages run in sequence, never in parallel — both saturate the Neural Engine.
Diarization failure is survivable and marks the meeting `degraded`; ASR failure
fails the run. Nothing partial is ever persisted, so there is no resume state.

**Channels are sources.** `AudioSourcePreparer` folds every channel into one
before anything reads the file, because `AVAudioConverter` — which FluidAudio
and `SpeechAnalyzer` both use to reach 16 kHz mono — keeps channel 0 and drops
the rest rather than mixing; that is why system audio was never transcribed at
all. For Konfer's own recordings it also writes the two sides out separately
(`PreparedAudio.sides`), diarizes each on its own, and attributes each word to
the side that was louder while it was spoken (`SideEnvelope`,
`SideAttribution`, `SpeakerAligner.align(words:across:envelopes:)`), so a voice
in the room is never merged with a voice on the call. Transcription still runs
once, over the fold: doubling diarization costs 29 s an hour, doubling ASR
would cost ten minutes. **Whether a file has two sources is never inferred** —
only `RecorderView` claims it (`enqueue(separatesSources:)`), and
`Meeting.hasSeparateSources` remembers it for a re-run. See README ▸ "Two
channels, one transcript".

**Backends.** The model is derived, not chosen: `ASRBackendKind(transcribing:)`
maps each of the ten `MeetingLanguage` cases to one of three backends — Apple
for the six locales it covers, KB-Whisper Large for Swedish, stock Whisper
large-v3 for Danish, Dutch and Polish. There is no model setting and no
automatic case in either enum: the user declares the language in `ImportSheet`
(defaulting to English) and everything follows. `KONFER_BACKEND` overrides the
mapping for benchmarking, which is the only way to reach a model/language
mismatch; `TranscriptionPipeline` guards that up front, before diarization
spends a minute on the file. Transcripts written before the automatic option
went away say `"auto"` on disk and decode as Swedish, which is what they ran
as; `MeetingStore` silently drops what it cannot decode, so that fallback is
load-bearing.

`AppleSpeechBackend` is the one backend not bound to a single model: Apple
installs assets **per locale**, so `prepare`/`isPrepared` take a
`MeetingLanguage` and `resolvedLocale(for:)` picks a variant — the user's own
region when it exists (`de-AT` for an Austrian), else the language's home
region. That is why the whole `TranscriptionBackend` protocol is
language-parameterised.

**Models are downloaded on purpose.** `ManagedModel` is the catalogue of what
Konfer fetches itself (diarization, KB-Whisper Large, Whisper large-v3),
wrapping three different mechanisms: FluidAudio's loader, `KBWhisperModelStore`
(a hand-rolled fetch of a hardcoded file list, because KBLab's repo is not in
WhisperKit's layout) and `WhisperKitModelStore` (WhisperKit's own downloader,
for `argmaxinc/whisperkit-coreml`, whose folders carry files that list lacks).
Both stores write under one directory so Settings ▸ Models measures and deletes
in one place. `ModelDownloadQueue` runs them one at a time and lives in
`AppEnvironment` because `WelcomeWindow`, `ModelDownloadsWindow` and Settings
all drive the same queue; its fetching is injected (`Fetcher`) so the state
machine is testable without downloading gigabytes. `ImportSheet` disables
Transcribe when the language's model is missing and `TranscriptionPipeline`
guards it again — Apple's languages and `KONFER_BACKEND` are exempt, the former
because macOS installs those itself.

`BackendRegistry` is an actor that keeps loaded models resident;
Settings ▸ Models calls `unloadAll()` before deleting model files from disk.
Long recordings are cut into at most 4 coarse slices at real silences and
transcribed concurrently — WhisperKit's own chunking is deliberately off.

**Translation** (`All Platforms/Translation/`). Not a fourth pipeline stage:
an action on a finished transcript, because at a measured 0.34 s per turn a
meeting costs about two minutes — cheap enough to run twice, far too slow to
run unasked. `TranscriptTranslator` is an actor around Apple's
`TranslationSession`, which is a class and not `Sendable`, so it is made, used
and released inside the actor. `TranslationQueue` sits in front of it in
`AppEnvironment` beside `VideoExportQueue`, with its translator injected
(`Translator`) so the state machine is testable without a language pack — the
same bargain `ModelDownloadQueue.Fetcher` makes. Unlike the video queue it
writes lines through *as they arrive*, because half a translation is genuinely
half a translation: the pane shows the original for every turn that has none.

The models are macOS's, not Konfer's, so they are deliberately **not** in
`ManagedModel` or Settings ▸ Models — the same position as Apple's speech
locales. A headless session reports `canRequestDownloads == false`, so
`TranslationDownloadPrompt` is an empty SwiftUI view whose `.translationTask`
exists only to call `prepareTranslation()` and raise the system's download
sheet. Its closure must be `@Sendable`, or default-`MainActor` isolation makes
it receive a non-`Sendable` session across an isolation boundary.

`Meeting.translation` keys lines by utterance id, and **every operation in
`Meeting+Editing.swift` that rewrites a turn's text or folds two turns together
must drop the affected lines** — `splitUtterance` is the trap, since the head
keeps the original id while its text changes. `TranslationSupport` records the
four pairs macOS refuses (sv↔pl, da↔pl); they are refused rather than pivoted
through English. `SubtitleExporter.redistribute` spreads a translated turn
across the cues its original was cut into, so no time is ever invented.

**Persistence.** `MeetingStore` is one JSON file per meeting under
`~/Library/Application Support/Konfer/Meetings/`, write-through on every
mutation. Audio is never copied: a `Meeting` holds `audioPath`, so a meeting whose
recording moved still opens read-only. `WaveformStore` caches envelopes beside the
transcript. `SpeakerStore` holds cross-meeting voice enrollment and only ever
*suggests* a name — never applies one automatically.

**Transcript model** (`Pipeline/Transcript.swift`). An `Utterance` carries a
`speakerId` into the meeting's `SpeakerLabel` roster rather than a name, which is
what makes rename/merge/reassign cheap. `words: [WordSpan]?` drives word-level
playback highlighting and is dropped when text is hand-edited. Editing operations
live in `Meeting+Editing.swift` and are covered by `MeetingEditingTests`.

**Recording** (`All Platforms/Recording/`). `RecordingSource` has two
implementations chosen by the user: `AggregateDeviceRecorder` (Core Audio
process tap) and `ScreenCaptureRecorder` (ScreenCaptureKit). Both need consent,
and the difference is which: a tap asks for *System Audio Recording*
(`kTCCServiceAudioCapture`, needs `NSAudioCaptureUsageDescription` in
`Info.plist` — the `INFOPLIST_KEY_` build setting for it is ignored, so check
the built bundle with `plutil -p`), ScreenCaptureKit for the full screen
recording. Both are rows of the same Settings pane. **A refused tap is silent**:
every call returns `noErr` and every buffer is zeros, which is why
`RecorderController` watches the level and warns after four seconds rather than
trusting a status code.
Both honour the same contract — microphone on channel 0, system audio on channel 1
via `TwoChannelWriter`. Keeping the sides apart is free while recording and
impossible to recover afterwards.

The microphone is optional (`RecordingConfiguration.recordsMicrophone`): a call
you are only listening to is recorded with channel 0 deliberately silent, which
`AudioSourcePreparer` then drops as "a side with nothing on it is not a side",
so the transcript marks every voice as being on the call. Off is a flag rather
than a nil `microphoneID`, because nil there already means the system default
— and `RecorderController.refreshDevices()` reassigns a nil id every couple of
seconds. Neither recorder opens an input device in that mode, so neither asks for the
microphone permission. `ScreenCaptureRecorder` simply omits the `.microphone`
stream output. `AggregateDeviceRecorder` cannot omit its microphone so easily —
an aggregate device needs a main sub-device to own its clock and a tap is not
one — so it builds the device around the default *output* device instead, which
contributes no input channels: measured against a real tap, the aggregate then
exposes one input stream of one channel (the mono tap) rather than two, and
channel 0 reads digital zero. That is why the "microphone first, tap last"
assumption in `render` and the channel-count floor are both conditional.

**UI.** `MacApp` registers the scenes (main, recorder, models, welcome,
settings, about, attributions, help). `WelcomeWindow` opens once from
`MainWindow`'s `RootView` — a view, not a scene modifier, because the check
reads `AppSettings.hasCompletedOnboarding` and a `Scene` has no environment. `Sidebar` is the `NavigationSplitView` driving
`SidebarSelection`, handles drag-and-drop and file import, and auto-selects the
meeting the pipeline just finished. Panes live in `macOS/Panes/`, with
`WaveformScrubber` and `PlayerController` behind playback.

## Conventions

- Every file starts with `//  Copyright © 2026 Martin Johannesson. All rights reserved.`
  (see `IDETemplateMacros.plist`).
- The project uses `PBXFileSystemSynchronizedRootGroup`, so adding or deleting
  files needs no `.pbxproj` edit.
- Swift 6 concurrency is used seriously: value types are `nonisolated ... Sendable`,
  stores and controllers are `@Observable @MainActor` with `@ObservationIgnored`
  dependencies, and shared caches are actors.
- Doc comments explain *why* a choice was made, often citing a measurement.
  Match that when adding code; a comment that only restates the signature is noise.
- Test names are full sentences describing behaviour
  ("A word straddling a boundary goes to the speaker it overlaps most").
- Do not credit Claude in commit messages.
