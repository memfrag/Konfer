# Snoopy

On-device transcription of multi-speaker meetings, in Swedish or English.
Drop in a recording and get a transcript where every line carries a timestamp
and a speaker. Nothing leaves the machine except the one-time model download.

## How it works

Three stages:

1. **Diarization** — [FluidAudio](https://github.com/FluidInference/FluidAudio)'s
   `OfflineDiarizerManager` (pyannote segmentation, WeSpeaker embeddings, VBx
   clustering) works out who spoke when.
2. **Speech recognition** — Apple's `SpeechTranscriber` for English,
   [KB-Whisper](https://huggingface.co/KBLab/kb-whisper-large) via
   [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) for Swedish.
   Both produce per-word timings.
3. **The merge** — `SpeakerAligner` attributes each word to the speaker segment
   it overlaps most, then groups words into turns. Nothing off the shelf joins
   these two halves; this is the part Snoopy adds.

Diarization and recognition run in sequence, not in parallel: both saturate the
Neural Engine, so concurrency buys nothing and makes progress meaningless.

## Choosing a model

Apple's `SpeechTranscriber` covers 30 locales and **Swedish is not one of them**,
so Swedish has to go elsewhere. KB-Whisper is the National Library of Sweden's
Whisper fine-tune, trained on more than 50,000 hours of Swedish.

Measured on the same five minutes of a real Swedish meeting (M3 Ultra):

| Model | Size | Speed | Opening line |
|---|---|---|---|
| Parakeet TDT v3 *(removed)* | 469 MB | 71× | "Reslånser om i ökonsättning, öka effektivitet och löns." |
| Canary-1B-v2 *(rejected)* | 567 MB | 15× | "Ställs det så att de blir. Ställ omsättning." |
| KB-Whisper small | 485 MB | 43× | "Theresas roll i snackomsättning, kreativiteten, lönsamhet…" |
| **KB-Whisper large** | 2.9 GB | 7.5× | **"Resans roll i att öka omsättning, öka effektiviteten och lönsamheten."** ✓ |

Canary was rejected despite a better benchmark WER: FluidAudio's build returns
no timestamps at all, and asking it for them (`<|timestamp|>`) makes its decoder
degenerate into a repetition loop. Parakeet was removed once Apple's transcriber
covered English better than it did.

Settings ▸ Transcription picks the model. **Automatic** — the default — sends
English to Apple and everything else to KB-Whisper Large.

## What a real meeting costs

A 1 h 17 m Swedish meeting on an M3 Ultra, KB-Whisper Large, models already
downloaded:

| Stage | Time |
|---|---|
| Diarization | 28.9 s |
| Transcription | 1359.7 s |
| **Total** | **25 min — 3× real time** |

12,418 words across 353 turns and 6 speakers, covering 88% of the recording's
duration. Peak memory about 1.4 GB.

Transcription dominates, and that is a deliberate trade — see below.

## Models

Downloaded once, on the first transcription:

- **KB-Whisper** → `~/Library/Application Support/Snoopy/Models/` (2.9 GB for
  large, 485 MB for small). The very first load also compiles the CoreML models
  for the Neural Engine, which takes a few minutes; every load after that is
  about a second.
- **Diarization** → `~/Library/Application Support/FluidAudio/Models/` (22 MB).
- **Apple's English models** are managed by macOS and need no download of ours.

Settings ▸ Models shows the sizes and deletes them; the next run downloads them
again. Every run after the first is fully offline.

### Why transcription isn't chunked

WhisperKit defaults to splitting a file on silence (`chunkingStrategy: .vad`)
and decoding the chunks across 16 concurrent workers. Snoopy turns that off,
and it costs more than twice the wall clock to do so.

It isn't simply that the detector is bad — though it is. Measuring the
recording's own frame energy against WhisperKit's fixed 0.02 threshold:

```
frames >= 0.02   67.8%   <- what EnergyVAD calls speech
noise floor (p5) 0.0033  -> six times BELOW the threshold
```

Background noise isn't tripping it; the opposite. A far-field mic leaves a
quarter of the speech *quieter* than the threshold. Lowering the threshold
doesn't help, because the chunker splits on the longest silence it can find —
remove the silences and it cuts mid-word instead, which is exactly what makes
Whisper hallucinate (507 words at threshold 0.005, 583 at 0.002).

Snoopy already runs pyannote before it transcribes, so `DiarizationVAD` hands
those segments to WhisperKit as the speech mask. That beats energy thresholding
comfortably — and still isn't enough. Five minutes of a real Swedish meeting:

| Strategy | Words | Covered | Time |
|---|---|---|---|
| `.vad`, WhisperKit's EnergyVAD | 606 | 66% | 33 s |
| `.vad`, `DiarizationVAD` | **483–791** | **51–86%** | 42 s |
| `.none` (Snoopy) | **813, 813** | **86%** | 93 s |

The range is not a typo. **Chunked transcription is not deterministic.** The
same file with the same settings and the same speech regions produced 791, 657
and 639 words on three consecutive runs; unchunked produced 813 twice,
identically. A chunk that fails to decode is dropped with only a debug log, so
with 16 workers a transient failure quietly removes part of the meeting — and
looks exactly like a pause.

A transcript that differs every time you produce it isn't worth halving the
wait for. `DiarizationVAD` stays in the tree because it makes the comparison
honest and re-runnable (`SNOOPY_CHUNKING=vad`), but chunking is off.

On the full hour, unchunked gives 88% coverage.

### Why the language tag matters

Left to detect language itself, Whisper decides **per VAD chunk** — and a
Swedish meeting sprinkled with "stakeholder" and "AI" makes chunks flip
language, which silently merges text from unrelated parts of the recording.
Snoopy always pins the language, treating Auto as Swedish.

## Reading

Clicking any word moves the playhead to it, so you can check a doubtful passage
against the audio without hunting for the spot. The current word highlights as
it plays.

Transcript text is deliberately **not** selectable while reading — dragging to
select and clicking to seek are the same gesture, and seeking is what you want
almost every time. Selection lives in edit mode; a line's context menu offers
**Copy Text** and **Copy with Speaker and Time** (`[00:12:34] Anna: …`, the same
attribution the Markdown export uses), and export covers the whole transcript.

## Editing

Both the diarizer and the recogniser make mistakes, so the transcript is a
document, not a printout:

- **Rename** a speaker to relabel every one of their lines at once.
- **Merge** two clusters that were the same person all along.
- **Reassign** a single misattributed line.
- **Split** a turn at the playhead when a speaker change happened mid-line, and
  **merge** a turn with the one before or after it when the diarizer broke one
  turn into two. The earlier turn wins: the result keeps its speaker and id.
- **Edit the text.** The turn keeps its start and end, but its word timings are
  dropped — the edited words are no longer the ones the model timed — and
  playback falls back to highlighting the whole line.

Naming a speaker also enrolls their voice, so later recordings offer them as a
suggestion. Suggestions are never applied automatically: a wrong guess would
stamp a real person's name across an hour of transcript, and "Speaker 2" is a
much better failure than the wrong name.

## Build

Requires Xcode 26 and macOS 26.

```sh
xcodebuild -scheme "Snoopy (Debug)" build
xcodebuild -scheme "Snoopy (Debug)" test
```

The app is **not** sandboxed, so the library can reference recordings wherever
they live. Transcripts persist as one JSON file per meeting in
`~/Library/Application Support/Snoopy/Meetings/`; audio is never copied, so a
meeting whose recording has moved still opens — read-only, with playback off.

### End-to-end check

`PipelineIntegrationTests` runs the real models against a real recording. It is
skipped unless you point it at one:

```sh
TEST_RUNNER_SNOOPY_AUDIO=/path/to/meeting.wav \
  xcodebuild test -scheme "Snoopy (Debug)" \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SnoopyTests/PipelineIntegrationTests
```

Keep test parallelization off: two runner processes sharing one model cache
corrupt each other's download.

## Out of scope

No live recording or streaming transcription, and no summarisation or other
LLM post-processing. Snoopy transcribes files and stops.

## License

See the LICENSE file for licensing information.
