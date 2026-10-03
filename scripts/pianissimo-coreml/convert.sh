#!/bin/bash
# Copyright © 2026 Martin Johannesson. All rights reserved.
set -euo pipefail

# -----------------------------------------------------------------------------
# Convert Klang Pianissimo to the CoreML models Konfer's ParakeetBackend runs:
# set up a Python 3.12 environment, download the pinned checkpoint and check
# it, export, compile, and optionally install into Konfer's models folder.
#
# Prerequisites:
#   - uv (brew install uv)
#   - Xcode command line tools, for coremlcompiler
#
# Usage:
#   ./scripts/pianissimo-coreml/convert.sh [--install] [--encoder-bits 8|16]
#
# Everything is written under scripts/pianissimo-coreml/build/, which git
# ignores. --install copies the compiled models to where Konfer looks for them.
# -----------------------------------------------------------------------------

# --- Constants ---
SOURCE_REPO="KlangAI/pianissimo-sv"
SOURCE_REVISION="8f1f6d8f8bd7482a5ea1d2bfaf6ef5be61597138"
SOURCE_FILE="pianissimo-sv.nemo"
SOURCE_SHA256="ca340b827dc9e18d2019341fa7b6dc163f00284d84066ce2cbfffcaa129920cd"
INSTALL_DIR="$HOME/Library/Application Support/Konfer/Models/pianissimo-sv-120s"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
VENV="$SCRIPT_DIR/.venv"
PYTHON="$VENV/bin/python"

# --- Arguments ---
INSTALL=0
ENCODER_BITS=8
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) INSTALL=1; shift ;;
        --encoder-bits) ENCODER_BITS="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

command -v uv >/dev/null || { echo "uv is required: brew install uv" >&2; exit 1; }
xcrun --find coremlcompiler >/dev/null || { echo "coremlcompiler not found: install Xcode" >&2; exit 1; }

# --- Environment ---
# Python 3.12, not newer: NeMo 2.3.1 does not install on 3.13+. And not 3.10,
# which NeMo's own lock pins: its SciPy wheels no longer load on macOS 26+.
if [[ ! -x "$PYTHON" ]]; then
    echo "==> Creating Python 3.12 environment"
    uv venv --python 3.12 "$VENV"
fi
uv pip install --python "$PYTHON" -r "$SCRIPT_DIR/requirements.txt"

# --- Checkpoint ---
mkdir -p "$BUILD_DIR"
CHECKPOINT="$BUILD_DIR/$SOURCE_FILE"
if [[ ! -f "$CHECKPOINT" ]]; then
    echo "==> Downloading $SOURCE_REPO@$SOURCE_REVISION"
    curl -L --fail -o "$CHECKPOINT.partial" \
        "https://huggingface.co/$SOURCE_REPO/resolve/$SOURCE_REVISION/$SOURCE_FILE"
    mv "$CHECKPOINT.partial" "$CHECKPOINT"
fi
echo "==> Checking $SOURCE_FILE"
echo "$SOURCE_SHA256  $CHECKPOINT" | shasum -a 256 --check --status \
    || { echo "Checksum mismatch: $CHECKPOINT is not the pinned revision" >&2; exit 1; }

# --- Export ---
PACKAGES="$BUILD_DIR/mlpackages"
COMPILED="$BUILD_DIR/compiled"
rm -rf "$PACKAGES" "$COMPILED"
echo "==> Exporting"
"$PYTHON" "$SCRIPT_DIR/convert.py" \
    --nemo "$CHECKPOINT" --out "$PACKAGES" \
    --source "$SOURCE_REPO@$SOURCE_REVISION" --encoder-bits "$ENCODER_BITS"

# --- Compile ---
echo "==> Compiling"
mkdir -p "$COMPILED"
for model in Preprocessor Encoder Decoder JointDecisionv3; do
    xcrun coremlcompiler compile "$PACKAGES/$model.mlpackage" "$COMPILED" >/dev/null
done
cp "$PACKAGES/parakeet_vocab.json" "$PACKAGES/conversion.json" "$COMPILED/"
du -sh "$COMPILED"

# --- Install ---
if [[ "$INSTALL" -eq 1 ]]; then
    echo "==> Installing to $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    cp -R "$COMPILED" "$INSTALL_DIR"
fi
echo "Done: $COMPILED"
