#!/usr/bin/env bash
# Multi-turn SFT on JoeYing/ReTool-SFT with current verl `sft_trainer`.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERL_ROOT="${VERL_ROOT:-/workspace}"
DATA_ROOT="${DATA_ROOT:-$KIT_ROOT/data/hf}"
export PYTHONPATH="${KIT_ROOT}:${VERL_ROOT}:${PYTHONPATH:-}"

nnodes="${NNODES:-1}"
nproc_per_node="${NPROC_PER_NODE:-8}"
project_name="${PROJECT_NAME:-retool_sft}"
experiment_name="${EXPERIMENT_NAME:-multiturn-sft-qwen2.5-7b-instruct}"

TRAIN_DATA="${TRAIN_DATA:-$DATA_ROOT/sft/train-00000-of-00001.parquet}"
EVAL_DATA="${EVAL_DATA:-$TRAIN_DATA}"
MODEL_PATH="${MODEL_PATH:-$HOME/models/Qwen/Qwen2.5-7B-Instruct}"
SAVE_PATH="${SAVE_PATH:-$DATA_ROOT/checkpoint/$experiment_name}"

mkdir -p "$SAVE_PATH"

torchrun --standalone --nnodes="$nnodes" --nproc_per_node="$nproc_per_node" \
  -m verl.trainer.sft_trainer \
  data.train_files="$TRAIN_DATA" \
  data.val_files="$EVAL_DATA" \
  data.max_length=16384 \
  data.train_batch_size="${TRAIN_BATCH_SIZE:-32}" \
  data.micro_batch_size_per_gpu="${MICRO_BSZ:-4}" \
  data.messages_key=messages \
  data.tools_key=tools \
  data.ignore_input_ids_mismatch=True \
  model.path="$MODEL_PATH" \
  model.use_remove_padding=true \
  engine=fsdp \
  engine.ulysses_sequence_parallel_size="${SP_SIZE:-4}" \
  trainer.default_local_dir="$SAVE_PATH" \
  trainer.project_name="$project_name" \
  trainer.experiment_name="$experiment_name" \
  trainer.logger='["console"]' \
  trainer.total_epochs="${TOTAL_EPOCHS:-6}" \
  trainer.save_freq="${SAVE_FREQ:-62}" \
  checkpoint.save_contents='[model,optimizer,extra,hf_model]' \
  "$@"
