#!/usr/bin/env bash
# Convert JoeYing/ReTool-SFT into MultiTurnSFTDataset parquet.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${DATA_ROOT:-${PAYLOAD_DIR:-$HOME/retool-offline-payload}/datasets}"
export PYTHONPATH="${KIT_ROOT}:${PYTHONPATH:-}"

python3 "$KIT_ROOT/recipe/retool/retool_sft_preprocess.py" \
  --tools-config "$KIT_ROOT/recipe/retool/sandbox_fusion_tool_config.yaml" \
  --local-dataset-path "${1:-$DATA_ROOT/JoeYing/ReTool-SFT}" \
  --save-path "${2:-$DATA_ROOT/sft/train-00000-of-00001.parquet}"
