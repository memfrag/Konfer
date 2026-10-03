#!/usr/bin/env python3
# Copyright © 2026 Martin Johannesson. All rights reserved.
"""Check a Pianissimo conversion against NeMo on real audio.

    python verify.py attention  --nemo pianissimo-sv.nemo --audio meeting.wav
    python verify.py encoder    --nemo pianissimo-sv.nemo --audio meeting.wav --models build/mlpackages
    python verify.py transcribe --nemo pianissimo-sv.nemo --audio meeting.wav --models build/mlpackages

attention   NeMo with the band mask against the checkpoint's own local
            attention. Should agree to ~1e-5; anything near 0.07 means random
            attention biases or dropout (see band_attention in convert.py).
encoder     The CoreML encoder against NeMo's, on one window: cosine and speed
            on each compute unit.
transcribe  A reference transcript: Konfer's windowing (120 s, 15 s overlap,
            stitched mid-overlap) with the CoreML encoder and NeMo's greedy TDT
            decoding. Konfer's own output should be within a percent or two.
            With --reference, NeMo's encoder instead: the exact baseline.
"""
import argparse
import time
from pathlib import Path

import coremltools as ct
import librosa
import numpy as np
import torch

import nemo.collections.asr as nemo_asr

from convert import band_attention

WINDOW, OVERLAP, RATE, SECONDS_PER_FRAME = 120.0, 15.0, 16000, 0.08


def load_model(path):
    model = nemo_asr.models.ASRModel.restore_from(str(path), map_location="cpu")
    model.eval()
    return model


def window(audio, offset_seconds):
    start = int(offset_seconds * RATE)
    return torch.tensor(audio[start:start + int(WINDOW * RATE)])[None]


def encode(model, x):
    with torch.no_grad():
        mel, length = model.preprocessor(input_signal=x, length=torch.tensor([x.shape[1]]))
        return mel, length, model.encoder(audio_signal=mel, length=length)[0]


def cosine(a, b):
    return float((a * b).sum() / np.linalg.norm(a) / np.linalg.norm(b))


def attention(args, audio):
    model = load_model(args.nemo)
    x = window(audio, args.offset)
    local = encode(model, x)[2]
    band_attention(model)
    banded = encode(model, x)[2]
    print(f"local vs banded over {x.shape[1] / RATE:.0f} s: max |diff| {(local - banded).abs().max():.2e}")


def encoder(args, audio):
    model = load_model(args.nemo)
    x = window(audio, args.offset)
    pad = int(WINDOW * RATE) - x.shape[1]
    mel, length, reference = encode(model, torch.nn.functional.pad(x, (0, pad)) if pad > 0 else x)
    reference = reference.numpy()
    feed = {"mel": mel.numpy().astype(np.float32), "mel_length": length.numpy().astype(np.int32)}
    for units in ("CPU_ONLY", "CPU_AND_GPU", "CPU_AND_NE"):
        coreml = ct.models.MLModel(str(args.models / "Encoder.mlpackage"), compute_units=getattr(ct.ComputeUnit, units))
        coreml.predict(feed)
        started = time.time()
        output = coreml.predict(feed)["encoder"]
        print(f"{units:12} {1000 * (time.time() - started):5.0f} ms  cosine {cosine(output, reference):.4f}"
              f"  max |diff| {np.abs(output - reference).max():.3f}")


def transcribe(args, audio):
    model = load_model(args.nemo)
    coreml = None if args.reference else ct.models.MLModel(
        str(args.models / "Encoder.mlpackage"), compute_units=ct.ComputeUnit.CPU_AND_GPU)
    size, step = int(WINDOW * RATE), int((WINDOW - OVERLAP) * RATE)
    starts = list(range(0, max(1, len(audio) - int(OVERLAP * RATE)), step))
    kept = []
    for index, start in enumerate(starts):
        piece = audio[start:start + size]
        padded = np.pad(piece, (0, size - len(piece)))
        with torch.no_grad():
            mel, length = model.preprocessor(input_signal=torch.tensor(padded)[None], length=torch.tensor([len(piece)]))
        with torch.no_grad():
            if coreml is None:
                encoded, encoded_length = model.encoder(audio_signal=mel, length=length)
            else:
                result = coreml.predict({"mel": mel.numpy().astype(np.float32),
                                         "mel_length": length.numpy().astype(np.int32)})
                encoded = torch.tensor(result["encoder"])
                encoded_length = torch.tensor(result["encoder_length"]).long()
            hypothesis = model.decoding.rnnt_decoder_predictions_tensor(
                encoder_output=encoded, encoded_lengths=encoded_length, return_hypotheses=True,
            )[0]
        offset = start / RATE
        keep_from = 0 if index == 0 else offset + OVERLAP / 2
        keep_until = float("inf") if index == len(starts) - 1 else offset + WINDOW - OVERLAP / 2
        for token, frame in zip(list(hypothesis.y_sequence), list(hypothesis.timestamp)):
            if keep_from <= offset + int(frame) * SECONDS_PER_FRAME < keep_until:
                kept.append(int(token))
    text = model.tokenizer.ids_to_text(kept)
    if args.output:
        args.output.write_text(text)
    print(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("check", choices=["attention", "encoder", "transcribe"])
    parser.add_argument("--nemo", required=True, type=Path)
    parser.add_argument("--audio", required=True, type=Path)
    parser.add_argument("--models", type=Path, help="directory with the .mlpackages")
    parser.add_argument("--offset", type=float, default=0, help="where the checked window starts, in seconds")
    parser.add_argument("--output", type=Path, help="transcribe: also write the text here")
    parser.add_argument("--reference", action="store_true",
                        help="transcribe: use NeMo's own encoder on the untouched checkpoint instead of CoreML")
    args = parser.parse_args()
    if args.check != "attention" and args.models is None and not args.reference:
        parser.error("--models is required for this check")

    audio, _ = librosa.load(str(args.audio), sr=RATE, mono=True)
    {"attention": attention, "encoder": encoder, "transcribe": transcribe}[args.check](args, audio)


if __name__ == "__main__":
    main()
