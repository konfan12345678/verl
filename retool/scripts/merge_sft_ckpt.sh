#!/usr/bin/env bash
# Merge an FSDP SFT shard dir into a Hugging Face checkpoint for GRPO.
set -euo pipefail

VERL_ROOT="${VERL_ROOT:-/workspace}"
export PYTHONPATH="${VERL_ROOT}:${PYTHONPATH:-}"

LOCAL_DIR="${1:?usage: $0 <global_step_xxx or actor dir> <target_hf_dir>}"
TARGET_DIR="${2:?usage: $0 <global_step_xxx or actor dir> <target_hf_dir>}"

if [[ -d "$LOCAL_DIR/actor" ]]; then
  LOCAL_DIR="$LOCAL_DIR/actor"
fi

python3 -m verl.model_merger merge \
  --backend fsdp \
  --local_dir "$LOCAL_DIR" \
  --target_dir "$TARGET_DIR"

echo "merged HF weights -> $TARGET_DIR"
