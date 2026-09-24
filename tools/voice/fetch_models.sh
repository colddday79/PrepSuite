#!/usr/bin/env bash
# Recreates the offline speech models used by packages/prepsuite_speech.
# The files are large and are NOT committed; run this after cloning.
#
#   tools/voice/fetch_models.sh            # Kroko English streaming ASR (default)
#   ASR=librispeech tools/voice/fetch_models.sh   # Apache-2.0 alternative (less accurate)
#   NORMAN_SRC=/path/en_US-norman-medium.onnx tools/voice/fetch_models.sh
#
# Sources: k2-fsa/sherpa-onnx GitHub releases (ASR model, espeak-ng-data) and
# the owner's Piper voice (default ~/Downloads, never modified). Python deps
# (onnx) come from PyPI into tools/voice/.venv.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
DEST="$ROOT/packages/prepsuite_speech/lib/assets/models"
CACHE="$HERE/.cache"
ASR="${ASR:-kroko}"
NORMAN_SRC="${NORMAN_SRC:-$HOME/Downloads/en_US-norman-medium.onnx}"
REL="https://github.com/k2-fsa/sherpa-onnx/releases/download"

# name|sha256 of the official release archives (checked after download).
KROKO="sherpa-onnx-streaming-zipformer-en-kroko-2025-08-06|c8676e5ff9ac2a85296e53ee0fd4d5fb1db6770e7a7647166eeafe349ade6834"
LIBRI="sherpa-onnx-streaming-zipformer-en-2023-06-26|639e25b578e9e997131402199419c13a941f8e4e198e2da1ce57dbf5cf401282"
ESPEAK="espeak-ng-data|4135ccf82e1f40613491c0874d4945ae9e9c7840933d8e25a6f9e003d9ebf533"
NORMAN_SHA="b9739443232a80a59c7d18810dd856899bf16a7964725f5ab81ea49b1351cb71"

mkdir -p "$CACHE"

fetch() { # tag name sha -> $CACHE/name.tar.bz2
  local tag="$1" name="$2" sha="$3" out="$CACHE/$2.tar.bz2"
  if [ ! -f "$out" ]; then
    echo "Downloading $name ($tag)…"
    curl -fL --retry 3 -o "$out.part" "$REL/$tag/$name.tar.bz2"
    mv "$out.part" "$out"
  fi
  echo "$sha  $out" | shasum -a 256 -c - >/dev/null || { echo "Checksum mismatch: $out" >&2; rm -f "$out"; exit 1; }
}

# --- Python venv for the Piper conversion (onnx from PyPI) ---
PY="$HERE/.venv/bin/python"
if ! "$PY" -c "import onnx" 2>/dev/null; then
  echo "Creating $HERE/.venv…"
  if command -v uv >/dev/null; then
    uv venv --python 3.13 "$HERE/.venv" >/dev/null
    uv pip install --python "$PY" "onnx==1.23.0" "sherpa-onnx==1.13.8" numpy >/dev/null
  else
    python3 -m venv "$HERE/.venv"
    "$HERE/.venv/bin/pip" install -q onnx "sherpa-onnx==1.13.8" numpy
  fi
fi

rm -rf "$DEST.new"
mkdir -p "$DEST.new/asr" "$DEST.new/tts/espeak-ng-data/lang/gmw"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$DEST.new"' EXIT

# --- Speech recognition (streaming zipformer transducer, int8) ---
if [ "$ASR" = "kroko" ]; then
  IFS='|' read -r name sha <<<"$KROKO"
  fetch asr-models "$name" "$sha"
  tar xjf "$CACHE/$name.tar.bz2" -C "$TMP" "$name/encoder.onnx" "$name/decoder.onnx" "$name/joiner.onnx" "$name/tokens.txt"
  for f in encoder.onnx decoder.onnx joiner.onnx tokens.txt; do mv "$TMP/$name/$f" "$DEST.new/asr/$f"; done
elif [ "$ASR" = "librispeech" ]; then
  IFS='|' read -r name sha <<<"$LIBRI"
  fetch asr-models "$name" "$sha"
  p="epoch-99-avg-1-chunk-16-left-128"
  tar xjf "$CACHE/$name.tar.bz2" -C "$TMP" "$name/encoder-$p.int8.onnx" "$name/decoder-$p.onnx" "$name/joiner-$p.int8.onnx" "$name/tokens.txt"
  mv "$TMP/$name/encoder-$p.int8.onnx" "$DEST.new/asr/encoder.onnx"
  mv "$TMP/$name/decoder-$p.onnx" "$DEST.new/asr/decoder.onnx"
  mv "$TMP/$name/joiner-$p.int8.onnx" "$DEST.new/asr/joiner.onnx"
  mv "$TMP/$name/tokens.txt" "$DEST.new/asr/tokens.txt"
else
  echo "ASR must be kroko or librispeech" >&2; exit 1
fi

# --- espeak-ng-data, English subset (bit-identical Norman output, 0.8 MB vs 18 MB) ---
IFS='|' read -r name sha <<<"$ESPEAK"
fetch tts-models "$name" "$sha"
E="espeak-ng-data"
tar xjf "$CACHE/$name.tar.bz2" -C "$TMP" "$E/phontab" "$E/phonindex" "$E/phondata" "$E/phondata-manifest" "$E/intonations" "$E/en_dict" "$E/lang/gmw/en"
for f in phontab phonindex phondata phondata-manifest intonations en_dict; do mv "$TMP/$E/$f" "$DEST.new/tts/$E/$f"; done
mv "$TMP/$E/lang/gmw/en" "$DEST.new/tts/$E/lang/gmw/en"

# --- Norman (Piper) → sherpa-onnx VITS bundle ---
[ -f "$NORMAN_SRC" ] && [ -f "$NORMAN_SRC.json" ] || { echo "Missing $NORMAN_SRC(.json)" >&2; exit 1; }
echo "$NORMAN_SHA  $NORMAN_SRC" | shasum -a 256 -c - >/dev/null || echo "warning: $NORMAN_SRC differs from the rhasspy/piper-voices release" >&2
"$PY" "$HERE/convert_piper.py" "$NORMAN_SRC" "$TMP/norman" >/dev/null
mv "$TMP/norman/model.onnx" "$DEST.new/tts/en_US-norman-medium.onnx"
mv "$TMP/norman/tokens.txt" "$DEST.new/tts/tokens.txt"

# --- manifest.json (file list + sizes; the app re-copies when it changes) ---
"$PY" - "$DEST.new" "$ASR" <<'PY'
import hashlib, json, os, sys
root, asr = sys.argv[1], sys.argv[2]
files = []
for d, _, names in os.walk(root):
    for n in sorted(names):
        p = os.path.join(d, n)
        files.append({"path": os.path.relpath(p, root), "bytes": os.path.getsize(p)})
files.sort(key=lambda f: f["path"])
h = hashlib.sha256(json.dumps(files).encode()).hexdigest()[:12]
json.dump({"version": f"{asr}-norman-{h}", "files": files}, open(os.path.join(root, "manifest.json"), "w"), indent=1)
PY

# Swap into place, keeping the committed README.
[ -f "$DEST/README.md" ] && cp "$DEST/README.md" "$DEST.new/README.md"
rm -rf "$DEST"
mv "$DEST.new" "$DEST"
echo "Models ready in ${DEST#$ROOT/}:"
(cd "$DEST" && du -sh asr tts && cat manifest.json | head -3)
