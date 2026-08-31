# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Snoopy is a non-sandboxed macOS 26 SwiftUI app (Xcode 26, Swift 6.2) that records
and transcribes multi-speaker meetings entirely on device, in Swedish or English.
Everything runs locally except the one-time model download.

Read `README.md` before changing the pipeline: it records the measurements behind
the non-obvious choices (why chunking is off, why slices are capped at 4, why the
language tag is pinned, why Canary and Parakeet were dropped). `Docs/BOILERPLATE.md`
describes the Apparata app template this started from — much of it no longer
matches the tree and it is not a guide to the current app.

## Build and test

```sh
xcodebuild -scheme "Snoopy (Debug)" build
xcodebuild -scheme "Snoopy (Debug)" test
```

Only `Snoopy (Debug)` and `Snoopy (Release)` are shared schemes; there is no plain
`Snoopy` scheme. Tests use swift-testing (`@Test`/`#expect`), not XCTest.

A single suite or test:

```sh
xcodebuild test -scheme "Snoopy (Debug)" -destination 'platform=macOS,arch=arm64' \
  -only-testing:SnoopyTests/SpeakerAlignerTests
```

Most tests are fixture-based — no models, no audio, no network. Three suites are
skipped unless you point them at a real recording, and they need the
`TEST_RUNNER_` prefix so `xcodebuild` forwards the variable to the test runner:

```sh
TEST_RUNNER_SNOOPY_AUDIO=/path/to/meeting.wav \
  xcodebuild test -scheme "Snoopy (Debug)" -destination 'platform=macOS,arch=arm64' \
  -only-testing:SnoopyTests/PipelineIntegrationTests
```

`PipelineIntegrationTests` also reads `SNOOPY_BACKEND`, `SNOOPY_LANGUAGE`,
`SNOOPY_FAST` and `SNOOPY_LIBRARY=real`; `RecordingSourceTests` needs
`SNOOPY_RECORD_APP`. Keep test parallelization off — two runner processes sharing
one model cache corrupt each other's download.

Runtime overrides for experiments: `SNOOPY_CHUNKING=vad`, `SNOOPY_SLICES=1`,
`SNOOPY_WHISPER_VERBOSE=1`, `SNOOPY_VAD_PADDING`, `SNOOPY_RECORD_DIAGNOSTICS=1`,
and `APP_ENVIRONMENT=mock` to launch against `AppEnvironment.mock()`.

`scripts/supported-locales.swift` (`swift scripts/supported-locales.swift`) lists
the locales Apple's `SpeechTranscriber` supports on this machine and which have
models installed — the check behind Snoopy's "English via Apple, everything else
via KB-Whisper" split. Swedish is not among the 30.

There is no SwiftLint config in the repo, but the sources carry
`// swiftlint:disable:next` comments; keep them if you move that code.

## Release

`scripts/build-and-notarize.sh` archives the `Snoopy (Release)` scheme, notarizes,
builds a DMG, signs for Sparkle, publishes a GitHub release and updates
`appcast.xml`. It expects `xcrun notarytool store-credentials 'notary'`,
`gh auth login`, and Sparkle EdDSA keys in the keychain.

The version lives in the build settings, not in `Info.plist`: the target sets
`GENERATE_INFOPLIST_FILE = YES`, so `CFBundleShortVersionString` and
`CFBundleVersion` are generated from `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` in `project.pbxproj`. Bump those; writing version keys
into `Snoopy/macOS/Info.plist` has no effect.

## Architecture

**Layering.** `Snoopy/All Platforms/` holds the model, pipeline, recording and
library layers; `Snoopy/macOS/` holds SwiftUI views, windows and commands.
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

**Backends.** `ASRBackendKind` selects `AppleSpeechBackend` (English) or
`WhisperKitBackend` (KB-Whisper small/large, everything else, Auto treated as
Swedish). `BackendRegistry` is an actor that keeps loaded models resident;
Settings ▸ Models calls `unloadAll()` before deleting model files from disk.
Long recordings are cut into at most 4 coarse slices at real silences and
transcribed concurrently — WhisperKit's own chunking is deliberately off.

**Persistence.** `MeetingStore` is one JSON file per meeting under
`~/Library/Application Support/Snoopy/Meetings/`, write-through on every
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
implementations chosen by the user: `AggregateDeviceRecorder` (Core Audio process
tap, no screen-recording prompt) and `ScreenCaptureRecorder` (ScreenCaptureKit).
Both honour the same contract — microphone on channel 0, system audio on channel 1
via `TwoChannelWriter`. Keeping the sides apart is free while recording and
impossible to recover afterwards.

**UI.** `MacApp` registers the scenes (main, recorder, settings, about,
attributions, help). `Sidebar` is the `NavigationSplitView` driving
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
