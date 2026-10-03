# Pianissimo → CoreML

Converts [Klang Pianissimo](https://huggingface.co/KlangAI/pianissimo-sv), Klang AI's Swedish fine-tune
of NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0), into the four CoreML models `ParakeetBackend` runs.

```sh
./scripts/pianissimo-coreml/convert.sh --install
```

The script needs `uv` and Xcode. It downloads the checkpoint at a pinned revision, checks its SHA-256,
exports, compiles, and with `--install` copies the result to
`~/Library/Application Support/Konfer/Models/pianissimo-sv-120s/`. It takes about two minutes after the
first run and peaks at about 7 GB of memory. `--encoder-bits 16` keeps the encoder at fp16 (1.2 GB rather
than about 700 MB).

## Publishing a release

Konfer downloads the conversion from its own GitHub releases, pinned in `PianissimoModelStore` by tag
and SHA-256.

```sh
./scripts/pianissimo-coreml/package.sh --release 2            # zip, manifest, size and SHA-256
./scripts/pianissimo-coreml/package.sh --release 2 --publish  # also creates the GitHub release
```

Then set `release` and `archiveSHA256` in `PianissimoModelStore.swift` to the printed values. A release
is never marked latest, because `build-and-notarize.sh` reads the latest release as the app's last
version. Each new conversion gets a new release number: replacing the asset under an existing tag
would break the pinned checksum in every copy of Konfer already out there.

`RELEASE_NOTES.md` becomes both the release's notes and the `README.md` inside the zip. It carries the
attribution CC BY 4.0 requires.

## Why convert it ourselves

Klang ships NeMo, ONNX and MLX. The community CoreML builds, such as
[markstrom/pianissimo-sv-coreml](https://huggingface.co/markstrom/pianissimo-sv-coreml), all use
FluidAudio's 15-second window. On a real Swedish meeting, a 15-second window loses whole phrases that
Klang's own 2-minute chunks keep. This conversion takes 120 seconds at a time.

Measured on the 1 h 17 m Kickoff meeting, as words different from Klang's fp32 MLX build:

| Build | Different | Transcribing |
|---|---|---|
| This conversion, 120 s, int8 encoder in blocks of 64 | 2.6% | 37.2 s |
| markstrom CoreML, 15 s, int8 encoder | 17.3% | 36.4 s |
| Klang MLX 8-bit | 1.6% | 42.3 s |

Klang's 8-bit build differs from fp32 by only 1.6%. So almost all of the 15-second build's gap comes
from the window, not from quantization.

## What the conversion does, and why

- **Local attention as a band mask.** The checkpoint uses `rel_pos_local_attn`, where each frame attends
  to 256 frames (about 20.5 s) on each side. That doesn't trace to CoreML. Full `rel_pos` attention with
  `att_context_size [256, 256]` computes the same function: NeMo builds the band mask itself, and the
  two agree to 4×10⁻⁶ over a 120-second window. Unrestricted full attention, which is what the
  15-second builds use, differs by 0.1 at this length. Below about 20 s the two are the same.
- **Two traps in `change_attention_model`, both handled by `band_attention`.** The checkpoint's attention
  layers have no biases. NeMo rebuilds them with biases, loads the weights non-strictly, and leaves the
  biases at their random initial values. Zeroed, they are exactly the checkpoint's layers. NeMo also
  builds the new modules in training mode, which turns attention dropout back on. Either trap alone
  moves the encoder by about 0.07 and looks like conversion error. The community 15-second builds
  switched attention the same way and appear to carry the random biases (cosine 0.997 against the
  checkpoint).
- **The preprocessor stays fp32.** In fp16 the power spectrum overflows and the spectrogram comes out NaN.
- **The encoder runs on the GPU, not the Neural Engine.** A 1501-frame attention matrix is more than the
  Neural Engine takes. Asked for `.cpuAndNeuralEngine`, CoreML silently runs the encoder on the CPU (560 ms
  a window), against 133 ms on the GPU.
- **How close it gets.** With the same 120-second windowing on five minutes of a real meeting, the fp16
  encoder on the GPU gives a transcript identical to NeMo's own, word for word: cosine 1.0000 on the
  encoder output. int8 weights in blocks of 64, the default, move 1.0% of the words, against 1.2% for
  Klang's own 8-bit build. Per-channel int8 moved 2.1%. On the CPU, CoreML's fp16 is noticeably less
  exact (cosine 0.998), another reason the encoder runs on the GPU.
- **Klang's MLX output is about 3% away from NeMo's.** That holds for both Klang's fp32 and 8-bit
  builds, so it comes from their pipeline (their own featurizer, and merging chunks by matching tokens
  rather than cutting mid-overlap), not from this conversion.
- **The decoder and joint don't depend on the window.** Their names and I/O match FluidAudio's
  (`Decoder`, `JointDecisionv3`), so the models stay interchangeable.

Tracing uses seeded noise rather than speech, because tracing only records shapes.

## Checking a conversion

```sh
PY=scripts/pianissimo-coreml/.venv/bin/python
B=scripts/pianissimo-coreml/build
$PY scripts/pianissimo-coreml/verify.py attention  --nemo $B/pianissimo-sv.nemo --audio meeting.wav
$PY scripts/pianissimo-coreml/verify.py encoder    --nemo $B/pianissimo-sv.nemo --audio meeting.wav --models $B/mlpackages
$PY scripts/pianissimo-coreml/verify.py transcribe --nemo $B/pianissimo-sv.nemo --audio meeting.wav --models $B/mlpackages
```

`transcribe` decodes the CoreML encoder's output with NeMo's own greedy TDT loop, using Konfer's
windowing. Konfer's `ParakeetBackend` re-implements that loop in Swift and should come within a percent
or two of it. The rest of the difference comes from resampling.

## Credit

The model is Klang AI AB's, under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). This changes
only its format: the weights are not retrained, the encoder's are quantized to int8 in blocks of 64, and
the local attention is expressed as a band mask. The export follows the structure of FluidInference's Parakeet v3
conversion in [mobius](https://github.com/FluidInference/mobius) (Apache 2.0).
