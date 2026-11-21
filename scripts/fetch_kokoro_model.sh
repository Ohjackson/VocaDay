#!/usr/bin/env bash
# Puts the Kokoro-82M weights and the five Listening voices into VocaDay/Resources/Kokoro.
# The files are large (about 315MB), so they stay out of git like BundledWords.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/VocaDay/Resources/Kokoro"
REPO="mlx-community/Kokoro-82M-bf16"
REV="a71e4d38b236d968966a2002c4c895dbd12b1c3c"
VOICES=(af_heart af_bella am_michael bf_emma bm_george)

mkdir -p "$DEST"

fetch() { # path in the model repo, file name in DEST
  local rel="$1" out="$DEST/$2"
  [ -s "$out" ] && return
  curl -fL --retry 3 -o "$out" "https://huggingface.co/$REPO/resolve/$REV/$rel"
  echo "ok  $2"
}

fetch kokoro-v1_0.safetensors kokoro-v1_0.safetensors
for v in "${VOICES[@]}"; do fetch "voices/$v.safetensors" "kokoro-voice-$v.safetensors"; done
du -sh "$DEST"
