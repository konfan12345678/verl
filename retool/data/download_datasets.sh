#!/usr/bin/env bash
# Download Hugging Face snapshots used by ReTool SFT + GRPO.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${DATA_ROOT:-$KIT_ROOT/data/hf}"
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"

mkdir -p "$DATA_ROOT"

download() {
  local repo="$1"
  local dest="$DATA_ROOT/$repo"
  mkdir -p "$(dirname "$dest")"
  python3 - << PY
from huggingface_hub import snapshot_download
import os
os.environ.setdefault("HF_ENDPOINT", "${HF_ENDPOINT}")
path = snapshot_download(
    repo_id="${repo}",
    repo_type="dataset",
    local_dir="${dest}",
)
print("ok", path)
PY
}

echo "DATA_ROOT=$DATA_ROOT"
download JoeYing/ReTool-SFT
download BytedTsinghua-SIA/DAPO-Math-17k
download Maxwell-Jia/AIME_2024
download yentinglin/aime_2025

echo
echo "Next: preprocess SFT parquet"
echo "  python3 $KIT_ROOT/recipe/retool/retool_sft_preprocess.py \\"
echo "    --local-dataset-path $DATA_ROOT/JoeYing/ReTool-SFT \\"
echo "    --save-path $DATA_ROOT/sft/train-00000-of-00001.parquet"
