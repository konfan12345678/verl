#!/usr/bin/env bash
# Optional extra parquet for DAPO / AIME if you prefer files over HF dirs.
# GRPO scripts can also pass the Hugging Face snapshot directories directly.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${DATA_ROOT:-$KIT_ROOT/data/hf}"
VERL_ROOT="${VERL_ROOT:-/workspace}"
export PYTHONPATH="${VERL_ROOT}:${KIT_ROOT}:${PYTHONPATH:-}"

python3 "$VERL_ROOT/examples/data_preprocess/dapo_multiturn_w_tool.py" \
  --local_dataset_path "$DATA_ROOT/BytedTsinghua-SIA/DAPO-Math-17k" \
  --local_save_dir "$DATA_ROOT/rl/dapo"

python3 "$VERL_ROOT/examples/data_preprocess/aime2024_multiturn_w_tool.py" \
  --local_dataset_path "$DATA_ROOT/Maxwell-Jia/AIME_2024" \
  --local_save_dir "$DATA_ROOT/rl/aime2024"

echo "DAPO parquet: $DATA_ROOT/rl/dapo/train.parquet"
echo "AIME parquet: $DATA_ROOT/rl/aime2024/train.parquet"
echo "Note: recipe CustomRLHFDataset already maps AIME 2024/2025 and DAPO when given snapshot dirs."
