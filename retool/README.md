---
cursor:
  subagentId: "bc-bee3e742-b9be-50b1-b4c5-af5a04b01916"
---

# Agentic RL 工具包（ReTool：SFT → GRPO 多轮代码工具）

把 **SFT 集、GRPO 集、代码沙箱部署、以及在当前 verl `main` 上跑完整多轮工具调用训练** 需要的文件集中在这一目录。

论文：[ReTool](https://arxiv.org/abs/2504.11536)。官方 recipe 在 [verl-recipe/retool](https://github.com/verl-project/verl-recipe/tree/main/retool)，verl 树内已不再带 `recipe/`。当前 `main` 还删掉了 `SandboxFusionTool`（`#6302`），所以本目录 **自带工具实现**。

910B 推理栈对齐日更镜像：`quay.io/ascend/verl:latest-vllm-910b-ubuntu`（vLLM / vllm-ascend 0.23.0）。详见 [`../verl-910b-vllm-images.md`](../verl-910b-vllm-images.md)。

## 目录

```text
docs/agentic-rl-retool/
  README.md                 ← 本文件
  datasets.md               ← SFT / GRPO 数据集说明
  configs/env.npu.sh        ← 910B 环境变量
  data/                     ← 下载 + 预处理脚本（HF 快照默认下到 data/hf/）
  tools/                    ← SandboxFusion 部署
  scripts/                  ← 7B SFT / merge / GRPO（GPU 与 910B）
  recipe/retool/            ← PYTHONPATH 可导入的 recipe 包
```

训练时把本目录加进 `PYTHONPATH`（脚本已做），**不必**改 verl 仓库。Agent Store 上的 `.sh` 可能没有可执行位，一律 `bash path/to/script.sh`。

## 一条龙（910B 推荐）

在 **verl 源码** 可用的环境里（NPU 容器内建议 `pip install --no-deps -e .` 覆盖镜像里的 verl，不要重装 vLLM）：

```bash
KIT=/cursor/stores/bc-61d43390-fa92-428f-8840-76ef6f1a11c6/docs/agentic-rl-retool
export VERL_ROOT=/workspace          # 你的 verl checkout
export DATA_ROOT=$KIT/data/hf
export PYTHONPATH=$KIT:$VERL_ROOT:$PYTHONPATH
export HF_ENDPOINT=https://hf-mirror.com   # 按网络情况

# 0) 内网：先在能上网的机器下载，再拷进 910B
# 详见 offline/OFFLINE.md
bash $KIT/offline/download_on_jumphost.sh          # 产物: $HOME/retool-offline-payload
# 内网容器:
#   bash $KIT/offline/install_on_intranet.sh
#   python3 $KIT/tools/local_run_code_server.py --python $HOME/retool-offline/python/bin/python3
export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code

# 1) 数据
bash $KIT/data/download_datasets.sh
bash $KIT/data/preprocess_sft.sh

# 2) 基座
# huggingface-cli download Qwen/Qwen2.5-7B-Instruct --local-dir $HOME/models/Qwen/Qwen2.5-7B-Instruct

# 3) SFT（教 hermes 工具格式）
export MODEL_PATH=$HOME/models/Qwen/Qwen2.5-7B-Instruct
bash $KIT/scripts/run_sft_qwen25_7b_npu.sh

# 4) 若 checkpoint 里没有现成 huggingface/ 子目录，再 merge
bash $KIT/scripts/merge_sft_ckpt.sh \
  $DATA_ROOT/checkpoint/multiturn-sft-qwen2.5-7b-instruct/global_step_xxx \
  $DATA_ROOT/checkpoint/multiturn-sft-qwen2.5-7b-instruct/huggingface

# 5) GRPO（真沙箱多轮）
export MODEL_PATH=$DATA_ROOT/checkpoint/multiturn-sft-qwen2.5-7b-instruct/huggingface
bash $KIT/scripts/run_grpo_qwen25_7b_npu.sh
```

GPU 把 `*_npu.sh` 换成 `run_sft_qwen25_7b.sh` / `run_grpo_qwen25_7b.sh`，不必 `source configs/env.npu.sh`。

## 两阶段在训什么

| 阶段 | 数据 | 工具是否真正执行 | 目标 |
| --- | --- | --- | --- |
| **SFT** | ReTool-SFT → parquet | 否，轨迹里已有 interpreter 返回 | 学会 `<tool_call>` / hermes 格式和读执行结果 |
| **GRPO** | DAPO-Math-17k，val=AIME | 是，每次 rollout 打 SandboxFusion | 学何时写代码、如何根据 stdout 得到 `\boxed{}` 答案 |

算法：`algorithm.adv_estimator=grpo`，clip 0.2–0.28（DAPO 非对称 clip，仍叫 GRPO estimator）。

Rollout：**只能 async**（当前 main 已删除 sync）。`agent_name=tool_agent` → `ToolAgentLoop`。NPU 上 sleep level 被压到 1，不要开 Prefill–Decode。

## 关键文件

| 路径 | 作用 |
| --- | --- |
| `recipe/retool/retool_sft_preprocess.py` | SFT 格式转换 |
| `recipe/retool/retool.py` | `CustomRLHFDataset` + `compute_score` + `CustomSandboxFusionTool` |
| `recipe/retool/sandbox_fusion_tools.py` | 从 verl 历史恢复的沙箱客户端（Ray 限流） |
| `recipe/retool/sandbox_fusion_tool_config.yaml` | 注册 `code_interpreter` |
| `scripts/run_*_npu.sh` | 910B 可跑脚本（相对昇腾文档：走当前 `sft_trainer`，reward 写在 `reward.custom_reward_function`） |

32B / PPO / GPT-OSS 上游脚本原样放在 `recipe/retool/run_qwen2-32b_*.sh`、`run_gpt_oss_ppo.sh`，路径仍假设 `recipe/retool/...` 且旧 `fsdp_sft_trainer`；**新训练用 `scripts/`**。

## 环境钉死

| 场景 | 栈 |
| --- | --- |
| 910B 跟当前 main | CANN 9.1.0，torch 2.10.0 / torch_npu 2.10.0.post4，vLLM 0.23.0 + vllm-ascend 0.23.0 |
| 官方 recipe README 的 pin | `verl==0.6.1`（历史；本目录已按 **当前 main** 改入口） |
| 昇腾 ReTool 最佳实践文档 | 仍写 CANN 9.0.0 + vLLM 0.18.0，**落后于日更镜像** |

## 训练时注意

- 控制台出现 `Failed to decode tool call` 在冷启动阶段正常。
- NPU 共卡更吃 HBM：脚本里 `gpu_memory_utilization=0.5`，可再降 `N_RESP` / `MAX_RESPONSE_LENGTH`。
- A2：`n_gpus_per_node=8`。不要拿 A3 镜像跑 910B。
- SFT 务必 `data.ignore_input_ids_mismatch=True`（Qwen 多轮 tool template 逐轮 tokenize 可能对不齐）。
- GRPO 前确认 `curl $SANDBOX_FUSION_URL` 能跑通，否则整轨工具结果都是错的，reward 会塌。

## 相关文档

- 数据集细节：[`datasets.md`](./datasets.md)
- 沙箱：[`tools/SANDBOX.md`](./tools/SANDBOX.md)
- 昇腾旧实践（版本已过期，流程仍有参考价值）：`verl/docs/ascend_tutorial/zh/model_support/examples/ascend_retool_best_practice.rst`
- Agent Loop：`verl/docs/advance/agent_loop.rst`、`verl/docs/start/agentic_rl.rst`
