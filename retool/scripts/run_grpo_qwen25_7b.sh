#!/usr/bin/env bash
# GRPO / DAPO-clip multi-turn tool RL on GPU (vLLM async + SandboxFusion).
set -x
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERL_ROOT="${VERL_ROOT:-/workspace}"
DATA_ROOT="${DATA_ROOT:-$KIT_ROOT/data/hf}"
export PYTHONPATH="${KIT_ROOT}:${VERL_ROOT}:${PYTHONPATH:-}"
export VLLM_USE_V1="${VLLM_USE_V1:-1}"
export SANDBOX_FUSION_URL="${SANDBOX_FUSION_URL:-http://127.0.0.1:8080/run_code}"

dapo_math_17k="${DAPO_PATH:-$DATA_ROOT/BytedTsinghua-SIA/DAPO-Math-17k}"
aime_2024="${AIME2024_PATH:-$DATA_ROOT/Maxwell-Jia/AIME_2024}"
aime_2025="${AIME2025_PATH:-$DATA_ROOT/yentinglin/aime_2025}"
model_path="${MODEL_PATH:-$DATA_ROOT/checkpoint/multiturn-sft-qwen2.5-7b-instruct/huggingface}"
tool_config_path="$KIT_ROOT/recipe/retool/sandbox_fusion_tool_config.yaml"
retool_py="$KIT_ROOT/recipe/retool/retool.py"

project_name="${PROJECT_NAME:-retool}"
experiment_name="${EXPERIMENT_NAME:-qwen2.5-7b_grpo}"
default_local_dir="${SAVE_PATH:-$DATA_ROOT/checkpoint/$experiment_name}"

adv_estimator=grpo
max_turns="${MAX_TURNS:-16}"
max_prompt_length=2048
max_response_length="${MAX_RESPONSE_LENGTH:-16384}"
actor_lr=1e-6
train_batch_size="${TRAIN_BATCH_SIZE:-64}"
ppo_mini_batch_size="${PPO_MINI_BATCH_SIZE:-16}"
n_resp_per_prompt="${N_RESP:-16}"
n_resp_per_prompt_val="${N_RESP_VAL:-8}"
infer_tp="${INFER_TP:-4}"
train_sp="${TRAIN_SP:-4}"
offload="${OFFLOAD:-True}"
n_gpus="${N_GPUS:-8}"

actor_max_token_len_per_gpu=$(( (max_prompt_length + max_response_length) * 1 ))
log_prob_max_token_len_per_gpu=$(( actor_max_token_len_per_gpu * 4 ))

python3 -m verl.trainer.main_ppo \
  algorithm.adv_estimator=$adv_estimator \
  algorithm.use_kl_in_reward=False \
  algorithm.kl_ctrl.kl_coef=0.0 \
  data.train_files="['$dapo_math_17k']" \
  data.val_files="['$aime_2025','$aime_2024']" \
  data.return_raw_chat=True \
  data.train_batch_size=$train_batch_size \
  data.max_prompt_length=$max_prompt_length \
  data.max_response_length=$max_response_length \
  data.filter_overlong_prompts=True \
  data.truncation='error' \
  data.custom_cls.path=$retool_py \
  data.custom_cls.name=CustomRLHFDataset \
  reward.custom_reward_function.path=$retool_py \
  reward.custom_reward_function.name=compute_score \
  actor_rollout_ref.model.path=$model_path \
  actor_rollout_ref.model.use_remove_padding=True \
  actor_rollout_ref.model.enable_gradient_checkpointing=True \
  actor_rollout_ref.actor.use_kl_loss=False \
  actor_rollout_ref.actor.kl_loss_coef=0.0 \
  actor_rollout_ref.actor.clip_ratio_low=0.2 \
  actor_rollout_ref.actor.clip_ratio_high=0.28 \
  actor_rollout_ref.actor.clip_ratio_c=10.0 \
  actor_rollout_ref.actor.optim.lr=$actor_lr \
  actor_rollout_ref.actor.use_dynamic_bsz=True \
  actor_rollout_ref.actor.ppo_mini_batch_size=$ppo_mini_batch_size \
  actor_rollout_ref.actor.ppo_max_token_len_per_gpu=$actor_max_token_len_per_gpu \
  actor_rollout_ref.actor.ulysses_sequence_parallel_size=$train_sp \
  actor_rollout_ref.actor.fsdp_config.param_offload=$offload \
  actor_rollout_ref.actor.fsdp_config.optimizer_offload=$offload \
  actor_rollout_ref.ref.log_prob_max_token_len_per_gpu=$log_prob_max_token_len_per_gpu \
  actor_rollout_ref.rollout.name=vllm \
  actor_rollout_ref.rollout.mode=async \
  actor_rollout_ref.rollout.tensor_model_parallel_size=$infer_tp \
  actor_rollout_ref.rollout.multi_turn.enable=True \
  actor_rollout_ref.rollout.multi_turn.max_user_turns=$max_turns \
  actor_rollout_ref.rollout.multi_turn.max_assistant_turns=$max_turns \
  actor_rollout_ref.rollout.multi_turn.tool_config_path=$tool_config_path \
  actor_rollout_ref.rollout.multi_turn.format=hermes \
  actor_rollout_ref.rollout.multi_turn.max_tool_response_length=4096 \
  actor_rollout_ref.rollout.agent.default_agent_loop=tool_agent \
  actor_rollout_ref.rollout.gpu_memory_utilization=0.8 \
  actor_rollout_ref.rollout.n=$n_resp_per_prompt \
  actor_rollout_ref.rollout.val_kwargs.top_p=0.6 \
  actor_rollout_ref.rollout.val_kwargs.temperature=1.0 \
  actor_rollout_ref.rollout.val_kwargs.n=$n_resp_per_prompt_val \
  trainer.logger='["console"]' \
  trainer.project_name=$project_name \
  trainer.experiment_name=$experiment_name \
  trainer.n_gpus_per_node=$n_gpus \
  trainer.val_before_train=True \
  trainer.log_val_generations=8 \
  trainer.nnodes=1 \
  trainer.save_freq=20 \
  trainer.default_local_dir=$default_local_dir \
  trainer.test_freq=10 \
  trainer.total_epochs=1 \
  "$@"
