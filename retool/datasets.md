# ReTool 数据集

论文：[ReTool: Reinforcement Learning for Strategic Tool Use in LLMs](https://arxiv.org/abs/2504.11536)

本套训练是 **两阶段**：SFT 冷启动工具格式 → GRPO 在真沙箱里学何时调用。

## 必下（默认 GRPO 配方）

| 阶段 | Hugging Face | 规模 | 用途 |
| --- | --- | --- | --- |
| **SFT** | [JoeYing/ReTool-SFT](https://huggingface.co/datasets/JoeYing/ReTool-SFT) | 2,000 条，约 5 MB | 带 `<code>` / `<interpreter>` / `<answer>` 的多轮代码轨迹；预处理后变成 `messages` + `tools` parquet |
| **GRPO 训练** | [BytedTsinghua-SIA/DAPO-Math-17k](https://huggingface.co/datasets/BytedTsinghua-SIA/DAPO-Math-17k) | 17k 数学题 | RL prompt；`CustomRLHFDataset` 会补 `\\boxed{}` 格式和 `agent_name=tool_agent` |
| **GRPO 验证** | [Maxwell-Jia/AIME_2024](https://huggingface.co/datasets/Maxwell-Jia/AIME_2024) | AIME 2024 | 910B 脚本默认 val |
| **GRPO 验证** | [yentinglin/aime_2025](https://huggingface.co/datasets/yentinglin/aime_2025) | AIME 2025 | GPU 脚本默认 val；论文指标用这套 |

基座模型（SFT 起点，不是数据集）：

- 7B（910B 单机 8 卡推荐）：[Qwen/Qwen2.5-7B-Instruct](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct)
- 32B（多机 GPU 配方）：[Qwen/Qwen2.5-32B-Instruct](https://huggingface.co/Qwen/Qwen2.5-32B-Instruct)

## 下载

内网机器不要直接跑下面的命令。在能上网的跳板机：

```bash
bash offline/download_on_jumphost.sh
# 国内: HF_ENDPOINT=https://hf-mirror.com bash offline/download_on_jumphost.sh
```

直链见 [`offline/URLS.md`](./offline/URLS.md)。拷到 910B 后 `DATA_ROOT=$HOME/retool-offline-payload/datasets`。

内网 payload 落盘：

```text
$HOME/retool-offline-payload/datasets/JoeYing/ReTool-SFT/train_2000.parquet
$HOME/retool-offline-payload/datasets/BytedTsinghua-SIA/DAPO-Math-17k/data/dapo-math-17k.parquet
$HOME/retool-offline-payload/datasets/Maxwell-Jia/AIME_2024/aime_2024_problems.parquet
$HOME/retool-offline-payload/datasets/yentinglin/aime_2025/data/*.parquet
```

SFT 预处理（镜像内已有 `datasets`，仍不必出网）：

```bash
export DATA_ROOT=$HOME/retool-offline-payload/datasets
bash data/preprocess_sft.sh
```

GRPO **不必**再转 parquet：`CustomRLHFDataset` 对 snapshot 目录调用 `datasets.load_dataset(path)["train"]`。若要离线 parquet，可跑 `data/preprocess_rl.sh`（依赖 `$VERL_ROOT/examples/data_preprocess/`）。

## SFT 预处理在做什么

`recipe/retool/retool_sft_preprocess.py` 把 ReTool-SFT 原文切成标准 chat：

1. 从第一条 message 抽出 `*user question:*` 之后的题目 → `role=user`
2. 第二条 message 循环解析：
   - `<code> ```python ... ``` </code>` → assistant + `tool_calls[code_interpreter]`
   - `<interpreter>...</interpreter>` → `role=tool`
   - `<answer>...</answer>` → 最终 assistant
3. 写入 `tools` 列为 `code_interpreter` 的 OpenAI schema（与 yaml 一致）

`MultiTurnSFTDataset` 用 `messages` + `tools` 做 chat template，只在 assistant token 上算 loss。

## GRPO 数据字段

`map_fn2`（DAPO）：在已有 `prompt` 后追加 `\boxed{}` 约束，并设 `agent_name=tool_agent`。  
`map_fn`（AIME）：拼 `prompt` / `reward_model.ground_truth` / `agent_name=tool_agent`。

Reward：`recipe/retool/retool.py::compute_score` 调 `math_dapo.compute_score`（严格 `\boxed{}`）。答错时按 `num_turns` 给一点工具调用 shaping，下限 `-0.6`。

## 不要混用的集

| 数据 | 为什么不作为本套默认 |
| --- | --- |
| `openai/gsm8k` + `gsm8k_tool_agent_loop.py` | 入门多轮可以，但依赖已删除的 `gsm8k_tool`；不是 ReTool 论文集 |
| CUDA `vllm==0.24` extra | NPU 镜像不要用 |
| 未预处理的原始 ReTool-SFT | SFT trainer 读的是 `messages/tools` parquet，不是原始两轮字符串 |
