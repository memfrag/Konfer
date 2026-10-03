# Klang Pianissimo — CoreML, 120-second window

An unofficial CoreML conversion of [Klang Pianissimo](https://huggingface.co/KlangAI/pianissimo-sv),
Klang AI AB's Swedish speech recognition model, a fine-tune of NVIDIA Parakeet TDT 0.6B v3. It's made for,
and used by, [Konfer](https://github.com/memfrag/Konfer), an on-device meeting transcriber for the Mac.

**All credit for the model goes to Klang AI AB.** This release only changes its format. The weights were
not retrained. It is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), like
the original.

## What is different from other CoreML builds

Other CoreML builds of Pianissimo take 15 seconds of audio at a time. This one takes 120 seconds, the
chunk length Klang's own MLX script uses. On a 1 h 17 m Swedish meeting, a 15-second build's transcript
differed from Klang's fp32 MLX build on 17.3% of words. Decoded as described below, this one differs on
2.6%.

## Files

One zip, `pianissimo-sv-120s.zip`, holding:

| File | |
|---|---|
| `Preprocessor.mlmodelc` | 16 kHz mono audio, up to 1,920,000 samples → 128-band log-mel. fp32 |
| `Encoder.mlmodelc` | FastConformer encoder, fixed 12,001 mel frames → 1,501 frames. int8 weights in blocks of 64 |
| `Decoder.mlmodelc` | TDT prediction network, one token per call |
| `JointDecisionv3.mlmodelc` | Joint network and decision head, one step: token, probability, duration index, top 64 |
| `parakeet_vocab.json` | Token id → SentencePiece piece |
| `conversion.json` | Window, frame rate, blank id, durations and other settings |
| `manifest.json` | Size and SHA-256 of every file |
| `README.md` | These notes |

The models are compiled for macOS 15 and later. Run the encoder on the GPU (`.cpuAndGPU`): a 1,501-frame
attention matrix is too large for the Neural Engine, and CoreML silently falls back to the CPU.

## Using it

Cut the audio into 120-second windows that overlap by 15 seconds. Zero-pad the last window and pass its
real length as `audio_length`. Preprocess and encode each window, then decode it with greedy TDT: blank
id 8192, durations [0, 1, 2, 3, 4], at most 10 symbols per frame, 0.08 s per encoder frame. Keep each
window's tokens between the midpoints of its overlaps. Konfer's
[`ParakeetBackend.swift`](https://github.com/memfrag/Konfer/blob/main/Konfer/All%20Platforms/Pipeline/ParakeetBackend.swift)
does exactly this.

## Changes from the original

Converted from `KlangAI/pianissimo-sv` revision `8f1f6d8f8bd7482a5ea1d2bfaf6ef5be61597138` (`pianissimo-sv.nemo`,
SHA-256 `ca340b827dc9e18d2019341fa7b6dc163f00284d84066ce2cbfffcaa129920cd`) with NeMo 2.3.1, PyTorch 2.7.0
and coremltools 9.0b1:

1. **Format:** exported to CoreML (ML Program) and compiled, as the four components above.
2. **Attention:** the checkpoint's local attention (256 frames on each side) is expressed as full
   relative-position attention under a band mask. It's the same function: the two agree to 2×10⁻⁶.
3. **Quantization:** the encoder's weights are int8, linear symmetric, in blocks of 64. With an fp16
   encoder, a five-minute transcript matches NeMo's word for word. The int8 encoder changes 1.0% of the
   words, against 1.2% for Klang's own 8-bit MLX build.

The conversion is reproducible with
[`scripts/pianissimo-coreml/convert.sh`](https://github.com/memfrag/Konfer/tree/main/scripts/pianissimo-coreml),
and its README records the measurements. The export follows the structure of FluidInference's Parakeet v3
conversion in [mobius](https://github.com/FluidInference/mobius).

## Citation

```bibtex
@misc{klang2026pianissimo,
  title = {Klang Pianissimo},
  author = {{Klang}},
  year = {2026},
  howpublished = {Hugging Face model repository},
  url = {https://huggingface.co/KlangAI/pianissimo-sv}
}
```
