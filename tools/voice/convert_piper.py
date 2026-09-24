#!/usr/bin/env python3
"""Convert a Piper voice (.onnx + .onnx.json) into a sherpa-onnx VITS bundle.

Follows https://k2-fsa.github.io/sherpa/onnx/tts/piper.html: copy the model,
add sherpa-onnx metadata to the copy, and write tokens.txt from phoneme_id_map.
The original files are never modified.

usage: convert_piper.py SRC.onnx OUT_DIR
"""
import json
import shutil
import sys
from pathlib import Path

import onnx


def main() -> None:
    src = Path(sys.argv[1]).expanduser()
    out_dir = Path(sys.argv[2])
    config = json.loads(Path(f"{src}.json").read_text(encoding="utf-8"))
    out_dir.mkdir(parents=True, exist_ok=True)

    with open(out_dir / "tokens.txt", "w", encoding="utf-8") as f:
        for symbol, ids in config["phoneme_id_map"].items():
            f.write(f"{symbol} {ids[0]}\n")

    meta = {
        "model_type": "vits",
        "comment": "piper",  # must be "piper" for Piper models
        "language": config["language"]["name_english"],
        "voice": config["espeak"]["voice"],
        "has_espeak": 1,
        "n_speakers": config["num_speakers"],
        "sample_rate": config["audio"]["sample_rate"],
    }
    dst = out_dir / "model.onnx"
    shutil.copyfile(src, dst)
    model = onnx.load(str(dst))
    keep = [p for p in model.metadata_props if p.key not in meta]
    del model.metadata_props[:]
    for p in keep:
        model.metadata_props.add(key=p.key, value=p.value)
    for key, value in meta.items():
        model.metadata_props.add(key=key, value=str(value))
    onnx.save(model, str(dst))
    print(f"wrote {dst} and tokens.txt; metadata={meta}")


if __name__ == "__main__":
    main()
