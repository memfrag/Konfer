#!/usr/bin/env python3
# Copyright © 2026 Martin Johannesson. All rights reserved.
"""Export Klang Pianissimo to the CoreML models Konfer's ParakeetBackend runs.

    python convert.py --nemo pianissimo-sv.nemo --out build/mlpackages

Writes Preprocessor, Encoder, Decoder and JointDecisionv3 .mlpackages, the
vocabulary and a conversion.json recording what was done. See README.md for why
each choice below was made.
"""
import argparse
import json
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from coremltools.optimize.coreml import (
    OpLinearQuantizerConfig, OptimizationConfig, linear_quantize_weights,
)

import nemo.collections.asr as nemo_asr

# Klang's own MLX script transcribes in 120-second chunks; so does Konfer.
WINDOW_SECONDS = 120.0
# The checkpoint's local attention: 256 encoder frames (~20.5 s) each side.
ATTENTION_CONTEXT = [256, 256]
AUTHOR = "Konfer conversion of Klang Pianissimo (Klang AI AB, CC BY 4.0)"


class Preprocessor(torch.nn.Module):
    def __init__(self, module):
        super().__init__()
        self.module = module

    def forward(self, audio_signal, audio_length):
        return self.module(input_signal=audio_signal, length=audio_length.long())


class Encoder(torch.nn.Module):
    def __init__(self, module):
        super().__init__()
        self.module = module

    def forward(self, mel, mel_length):
        return self.module(audio_signal=mel, length=mel_length.long())


class Decoder(torch.nn.Module):
    """The prediction network, one token at a time, LSTM state in and out."""

    def __init__(self, module):
        super().__init__()
        self.module = module

    def forward(self, targets, target_length, h_in, c_in):
        output, _, (h_out, c_out) = self.module(
            targets=targets.long(), target_length=target_length.long(), states=[h_in, c_in],
        )
        return output, h_out, c_out


class JointDecision(torch.nn.Module):
    """Joint network for one encoder frame and one decoder step, decided on the
    spot: the token, its probability, the TDT duration index, and the top 64
    tokens. Named and shaped like FluidAudio's JointDecisionv3."""

    def __init__(self, joint, vocab_size, durations, top_k=64):
        super().__init__()
        self.joint = joint
        self.tokens = vocab_size + 1  # plus blank
        self.durations = durations
        self.top_k = top_k

    def forward(self, encoder_step, decoder_step):
        encoded = self.joint.enc(encoder_step.transpose(1, 2))
        predicted = self.joint.pred(decoder_step.transpose(1, 2))
        hidden = self.joint.joint_net[0](encoded.unsqueeze(2) + predicted.unsqueeze(1))
        logits = self.joint.joint_net[2](hidden)  # [0] activation, [1] dropout
        token_logits = logits[..., : self.tokens]
        duration_logits = logits[..., -self.durations :]

        token_id = torch.argmax(token_logits, dim=-1).to(torch.int32)
        token_prob = torch.gather(
            torch.softmax(token_logits, dim=-1), -1, token_id.long().unsqueeze(-1)
        ).squeeze(-1)
        duration = torch.argmax(duration_logits, dim=-1).to(torch.int32)
        top_k_logits, top_k_ids = torch.topk(token_logits, k=self.top_k, dim=-1)
        return token_id, token_prob, duration, top_k_ids.to(torch.int32), top_k_logits


def band_attention(model):
    """Swap the checkpoint's local attention for full attention under a band
    mask: the same function, but plain masked attention CoreML can convert.

    Two NeMo traps. change_attention_model builds its new modules with biases
    the checkpoint doesn't have, loads the weights non-strictly and leaves the
    biases at their random initial values: zeroed, they are exactly the
    checkpoint's bias-free layers. And it builds them in training mode, with
    attention dropout on. Either alone moves the encoder by about 0.07.
    """
    layers = model.encoder.layers
    present = [set(dict(layer.self_attn.named_parameters())) for layer in layers]
    model.change_attention_model("rel_pos", ATTENTION_CONTEXT)
    with torch.no_grad():
        for layer, names in zip(layers, present):
            for name, parameter in layer.self_attn.named_parameters():
                if name not in names:
                    assert name.endswith(".bias"), f"unexpected new parameter {name}"
                    parameter.zero_()
    model.eval()


def convert(module, example, inputs, outputs, description, precision=None):
    with torch.no_grad():
        traced = torch.jit.trace(module, example, strict=False, check_trace=False)
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=inputs,
        outputs=outputs,
        minimum_deployment_target=ct.target.macOS15,
        compute_units=ct.ComputeUnit.CPU_ONLY,
        **({"compute_precision": precision} if precision else {}),
    )
    model.short_description = description
    model.author = AUTHOR
    return model


def tensor(name, shape, dtype=np.float32):
    return ct.TensorType(name=name, shape=shape, dtype=dtype)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--nemo", required=True, type=Path, help="pianissimo-sv.nemo")
    parser.add_argument("--out", required=True, type=Path, help="directory for the .mlpackages")
    parser.add_argument("--source", default="KlangAI/pianissimo-sv", help="recorded in conversion.json")
    parser.add_argument("--encoder-bits", type=int, choices=[8, 16], default=8,
                        help="8: int8 weights in blocks of 64, ~700 MB (default); 16: fp16, 1.2 GB")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    model = nemo_asr.models.EncDecRNNTBPEModel.restore_from(str(args.nemo), map_location="cpu")
    band_attention(model)
    model.decoder._rnnt_export = True

    sample_rate = int(model.cfg.preprocessor.sample_rate)
    samples = int(WINDOW_SECONDS * sample_rate)
    # Tracing only needs the shapes; any audio of the right length will do.
    generator = torch.Generator().manual_seed(0)
    audio = 0.1 * torch.randn(1, samples, generator=generator)
    audio_length = torch.tensor([samples], dtype=torch.int32)

    preprocessor = Preprocessor(model.preprocessor.eval())
    encoder = Encoder(model.encoder.eval())
    decoder = Decoder(model.decoder.eval())
    durations = list(model.cfg.model_defaults.tdt_durations)
    vocab_size = int(model.tokenizer.vocab_size)
    joint = JointDecision(model.joint.eval(), vocab_size, len(durations))

    with torch.no_grad():
        mel, mel_length = preprocessor(audio, audio_length)
        mel_length = mel_length.to(torch.int32)
        encoded, _ = encoder(mel, mel_length)
    print(f"window {WINDOW_SECONDS:.0f} s: mel {tuple(mel.shape)}, encoder {tuple(encoded.shape)}")

    # The power spectrum overflows fp16: the preprocessor must stay fp32.
    convert(
        preprocessor, (audio, audio_length),
        [tensor("audio_signal", (1, ct.RangeDim(1, samples))), tensor("audio_length", (1,), np.int32)],
        [tensor("mel", None), tensor("mel_length", None, np.int32)],
        f"Pianissimo preprocessor ({WINDOW_SECONDS:.0f} s window)", ct.precision.FLOAT32,
    ).save(str(args.out / "Preprocessor.mlpackage"))
    print("saved Preprocessor")

    encoder_model = convert(
        encoder, (mel, mel_length),
        [tensor("mel", tuple(mel.shape)), tensor("mel_length", (1,), np.int32)],
        [tensor("encoder", None), tensor("encoder_length", None, np.int32)],
        f"Pianissimo encoder ({WINDOW_SECONDS:.0f} s window, local attention ±256 frames)",
    )
    if args.encoder_bits == 8:
        # Blocks of 64, as Klang quantizes its own 8-bit MLX build. Per channel
        # moved 2.1% of a five-minute transcript's words; blocks of 64, 1.0%.
        encoder_model = linear_quantize_weights(encoder_model, OptimizationConfig(
            global_config=OpLinearQuantizerConfig(
                mode="linear_symmetric", granularity="per_block", block_size=64,
            ),
        ))
    encoder_model.save(str(args.out / "Encoder.mlpackage"))
    print(f"saved Encoder ({args.encoder_bits}-bit weights)")

    layers, hidden = int(model.decoder.pred_rnn_layers), int(model.decoder.pred_hidden)
    blank = int(model.decoder.blank_idx)
    targets = torch.full((1, 1), blank, dtype=torch.int32)
    target_length = torch.tensor([1], dtype=torch.int32)
    state = torch.zeros(layers, 1, hidden)
    with torch.no_grad():
        decoded, _, _ = decoder(targets, target_length, state, state)

    convert(
        decoder, (targets, target_length, state, state),
        [tensor("targets", (1, 1), np.int32), tensor("target_length", (1,), np.int32),
         tensor("h_in", tuple(state.shape)), tensor("c_in", tuple(state.shape))],
        [tensor("decoder", None), tensor("h_out", None), tensor("c_out", None)],
        "Pianissimo TDT prediction network",
    ).save(str(args.out / "Decoder.mlpackage"))
    print("saved Decoder")

    encoder_step = encoded[:, :, :1].contiguous()
    decoder_step = decoded[:, :, :1].contiguous()
    convert(
        joint, (encoder_step, decoder_step),
        [tensor("encoder_step", tuple(encoder_step.shape)), tensor("decoder_step", tuple(decoder_step.shape))],
        [tensor("token_id", None, np.int32), tensor("token_prob", None), tensor("duration", None, np.int32),
         tensor("top_k_ids", None, np.int32), tensor("top_k_logits", None)],
        "Pianissimo joint network and decision head, one step",
    ).save(str(args.out / "JointDecisionv3.mlpackage"))
    print("saved JointDecisionv3")

    pieces = {str(i): model.tokenizer.ids_to_tokens([i])[0] for i in range(vocab_size)}
    (args.out / "parakeet_vocab.json").write_text(json.dumps(pieces, ensure_ascii=False))
    (args.out / "conversion.json").write_text(json.dumps({
        "source": args.source,
        "window_seconds": WINDOW_SECONDS,
        "window_samples": samples,
        "mel_frames": int(mel.shape[-1]),
        "encoder_frames": int(encoded.shape[-1]),
        "encoder_seconds_per_frame": float(model.cfg.preprocessor.window_stride) * 8,
        "attention": f"rel_pos, att_context_size {ATTENTION_CONTEXT} (equivalent to rel_pos_local_attn)",
        "encoder_weights": "int8, blocks of 64" if args.encoder_bits == 8 else "fp16",
        "blank_id": blank,
        "durations": durations,
        "max_symbols": int(model.cfg.decoding.greedy.get("max_symbols", 10)),
        "decoder_layers": layers,
        "decoder_hidden": hidden,
    }, indent=2))
    print("done")


if __name__ == "__main__":
    main()
