#!/bin/zsh
# `make model`: model araçları ortamını kurar ve modeli Core ML'e çevirir (eşitlik kapılı).
set -euo pipefail
cd "$(dirname "$0")/../tools/model"
[ -d .venv ] || uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python torch facenet-pytorch "coremltools>=8.0" numpy pillow >/dev/null
.venv/bin/python convert.py
