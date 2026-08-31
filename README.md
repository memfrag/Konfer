# Snoopy

On-device transcription of multi-speaker meetings, in ten languages.
Drop in a recording and get a transcript where every line carries a timestamp
and a speaker. Nothing leaves the machine except the models themselves, which
are downloaded once, on purpose, before anything runs.

## How it works

Three stages:

1. **Diarization** — [FluidAudio](https://github.com/FluidInference/FluidAudio)'s
   `OfflineDiarizerManager` (pyannote segmentation, WeSpeaker embeddings, VBx
   clustering) works out who spoke when.
2. **Speech recognition** — Apple's `SpeechTranscriber` where it has the
   language, [KB-Whisper](https://huggingface.co/KBLab/kb-whisper-large) for
   Swedish and stock Whisper large-v3 for the rest, both via
   [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift). All produce
   per-word timings.
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

There is no model picker. Each row above has one sensible reading, so the
language you declare for a recording decides:

| Language | Model | Why |
|---|---|---|
| English, German, Spanish, French, Italian, Portuguese | Apple | Nine times faster, and nothing for Snoopy to download |
| Swedish | KB-Whisper Large | Apple has no Swedish; this was trained for it |
| Danish, Dutch, Polish | Whisper large-v3 | Neither of the others can do them |

Apple's `SpeechTranscriber` covers 30 locales — run
`swift scripts/supported-locales.swift` to see them, and which are installed on
a given Mac. Danish, Dutch and Polish are not among them, and neither is
Swedish, which is why stock Whisper is here alongside KB-Whisper's Swedish
specialist. Settings ▸ Transcription shows the routing and what each costs.
`SNOOPY_BACKEND` forces one model regardless, for comparing them on the same
recording.

## What a real meeting costs

A 1 h 17 m Swedish meeting on an M3 Ultra, KB-Whisper Large, models already
downloaded:

| Stage | Time |
|---|---|
| Diarization | 28.9 s |
| Transcription | 585.0 s |
| **Total** | **10.3 min — 7× real time** |

12,383 words across 356 turns and 6 speakers, covering 87% of the recording's
duration. Peak memory about 1.4 GB.

## Models

Snoopy asks for its models rather than fetching them behind your back. A
recording whose language needs a model that isn't downloaded **won't start** —
the import sheet says which model and how big it is, and offers to fetch it.
Three gigabytes arriving in the middle of a transcription you already committed
to is worse than being asked.

- **KB-Whisper** and **Whisper large-v3** →
  `~/Library/Application Support/Snoopy/Models/` (2.9 GB and about 3 GB). The
  very first load of each also compiles the CoreML models for the Neural
  Engine, which takes a few minutes; every load after that is about a second.
  Downloaded is not the same as ready.
- **Diarization** → `~/Library/Application Support/FluidAudio/Models/` (22 MB).
  Every transcription uses it, whatever the language. Small enough that it is
  the one download still fetched on demand, and a failure is survivable anyway.
- **Apple's models** are managed by macOS. There is nothing of ours to
  download, measure or delete — the first recording in a new language installs
  that locale itself, which is the one moment those languages need a network.

The first launch asks which languages you record in and queues exactly what
they need — for a user who only needs Apple's languages, that is nothing at
all. Window ▸ Models, or Settings ▸ Models, reopens it: it shows what each
model costs, downloads them one at a time, and deletes them. Everything after
that is offline.

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
honest and re-runnable (`SNOOPY_CHUNKING=vad`), but WhisperKit's chunking is off.

### Coarse slicing: the parallelism without the losses

WhisperKit's chunker caps every chunk at its 30-second window, so it can't be
asked for "four chunks" — five minutes is at least ten, an hour over a hundred,
and every seam is somewhere speech can go missing. Snoopy works one level up
instead: cut the recording into a **few long slices at real silences** (found in
the diarizer's segmentation), transcribe each in one complete unchunked pass,
and run the slices concurrently.

| Slices | Words | Covered | Time |
|---|---|---|---|
| 1 | 813 | 86% | 93 s |
| 2 | 811 | 86% | 54 s |
| 4 | **832, 832** | 86% | **42 s** |

Repeatable to the word, and no loss — a slice boundary in real silence costs
nothing, unlike a chunk boundary mid-sentence. On the full hour it takes 10.3
minutes instead of 25, for 12,383 words against 12,418: a 0.3% difference rather
than 25%.

Two constraints learned the hard way. Concurrency is capped at 4 because the
Neural Engine is one shared resource — eight simultaneous ten-minute decodes
make CoreML give up with *"ANE op async execution has timed out"*. And a slice
that fails comes back as a `Result` we inspect and surface as an error, which is
precisely what WhisperKit's own chunker does not do.

`SNOOPY_SLICES=1` restores a single pass.

Cut positions are chosen in two steps: diarization gaps give the rough places,
then the audio itself decides the exact ones, by finding the quietest 0.3s
window within fifteen seconds. That second step exists because the waveform view
showed the first step wasn't reliable — one cut in three landed on a passage
louder than the 75th percentile. After it, all three sit at or below the 25th.

## The waveform

The player is a waveform, coloured by who is speaking in the same colours as the
speaker chips, so the shape of a meeting reads at a glance: who talks most,
where the long stretches are, who only chips in. Yellow lines mark the
transcription cuts. Click or drag anywhere to seek.

Envelopes are computed once per meeting (peak amplitude, 2000 buckets) and
cached beside the transcript, since reading an hour of audio takes a few
seconds.

### Why the language tag matters

Left to detect language itself, Whisper decides **per VAD chunk** — and a
Swedish meeting sprinkled with "stakeholder" and "AI" makes chunks flip
language, which silently merges text from unrelated parts of the recording.
Snoopy always pins the language.

Which is why there is no automatic setting and no default: the import sheet
opens with the language unset and will not start until one is chosen. Guessing
picks the model, and a wrong guess doesn't degrade an hour of transcript so much
as replace it with something else.

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

Snoopy is released under the [BSD Zero Clause License](LICENSE) — do what you
like with it, no attribution required.

Its dependencies and the speech models it downloads are other people's work,
under their own licences, and one of them (the speaker diarization models,
CC BY 4.0) does require attribution. They are all listed in
[ATTRIBUTIONS.md](ATTRIBUTIONS.md).
