---
cursor:
  subagentId: "bc-bee3e742-b9be-50b1-b4c5-af5a04b01916"
---

# 其它会话请直接复制「PROMPT 正文」整段作为第一条用户消息

下面从 `---` 到文末 `END PROMPT` 是完整交接 prompt。

---

你是 Cursor 里的工程助手。用简体中文回答。继续 **verl + Ascend 910B + ReTool 多轮工具调用（SFT → GRPO）** 这条线，不要重新调研已经定案的镜像/配方，除非用户明确要求改方案。

## 用户与目标

- 用户要在 **华为昇腾 910B / Atlas A2** 上做 **agentic RL**：ReTool 风格，模型调 `code_interpreter` 跑 Python，先 SFT 再 GRPO。
- **训练环境是内网，容器不能出网。** 不能在 910B 上 `git clone` / `pip install` / `huggingface-cli download`。
- 本机 Windows 目标目录：`C:\StudyMaterials\RL\verl\retool`（有网的跳板机）。下好后再把整个 `retool` 拷进 910B。
- 训练容器镜像（已定案）：`quay.io/ascend/verl:latest-vllm-910b-ubuntu`  
  等价：`ascendai/verl:latest-vllm-910b-ubuntu`。国内可试 `m.daocloud.io/quay.io/ascend/verl:latest-vllm-910b-ubuntu`。

## 已定案的技术事实（不要推翻）

### 镜像栈（910B × 当前 verl main）

- Dockerfile：`docker/ascend/Dockerfile.ascend_9.1.0_a2`
- 基座 CANN **9.1.0**，Ubuntu 22.04，Python **3.12**
- vLLM **0.23.0**（`VLLM_TARGET_DEVICE=empty`）+ vllm-ascend 分支 `releases/v0.23.0`
- torch 2.10 / torch_npu，transformers **5.10.4**，MindSpeed/Megatron core_r0.18.0
- `supported_tags.md` 若仍写 CANN 9.0.0 是过期的，以 Dockerfile 为准
- **禁止**：A3 镜像（`*-a3-*`）、纯 vllm-ascend `v0.26.0rc2`、在 NPU 镜像里装 CUDA vLLM extra
- 覆盖镜像内过期 verl：`pip install --no-deps -e .`，**不要重装 vLLM / vllm-ascend**
- NPU rollout：**只能 async**；sleep level 1；不要 Prefill–Decode
- 工具名必须是 **`code_interpreter`**（SFT 轨迹 / yaml / DAPO `tools_kwargs` 一致）
- 当前 verl `main` 已删除树内 `recipe/` 和 `verl.tools.sandbox_fusion_tools`（PR `#6302`）。kit 自带 `recipe.retool.retool.CustomSandboxFusionTool`

### ReTool 两阶段

| 阶段 | 数据 | 是否真执行代码 | 入口 |
| --- | --- | --- | --- |
| SFT | `JoeYing/ReTool-SFT` → parquet | 否 | `verl.trainer.sft_trainer`，`data.ignore_input_ids_mismatch=True` |
| GRPO | 训 `BytedTsinghua-SIA/DAPO-Math-17k`，val `Maxwell-Jia/AIME_2024`（论文指标也可用 `yentinglin/aime_2025`） | 是，HTTP `/run_code` | `verl.trainer.main_ppo`，`algorithm.adv_estimator=grpo`，clip 0.2–0.28 |
| 基座 | `Qwen/Qwen2.5-7B-Instruct`（约 15GB，脚本默认不下） | — | SFT 起点 |

Rollout：`actor_rollout_ref.rollout.mode=async`，`multi_turn.enable=True`，`format=hermes`，`default_agent_loop=tool_agent`，`max_tool_response_length=4096`（默认 256 太短）。NPU 上 `gpu_memory_utilization` 默认 **0.5**。

Reward：`recipe.retool.retool.compute_score` → `math_dapo`（严格 `\boxed{}`）。

### 工具怎么跑（内网 910B 镜像内）

镜像 **没有 dockerd、没有 conda**。不要 `docker run volcengine/sandbox-fusion:...`，也不要把 SandboxFusion / poetry 装进系统 Python 3.12（`pydantic<2.7` + `transformers 4.x` 会打坏训练栈）。

内网推荐：

1. 便携 **CPython 3.10**（python-build-standalone，aarch64 + x86_64 都带，安装时按 `uname -m` 选）
2. manylinux **cp310** wheel：numpy 1.26.4、scipy 1.11.4、pandas 2.2.2、sympy、mpmath
3. 用镜像自带 `python3` 跑 kit 里的 **`tools/local_run_code_server.py`**（stdlib HTTP，兼容 SandboxFusion `/run_code` JSON）
4. 真正 exec 用户代码的解释器是便携 3.10，不是训练用的 3.12
5. `export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code`

不要跑官方 `runtime/python/install-python-runtime.sh` 全量（tensorflow/torch/PyQt，aarch64 容易挂）。ReTool 数学用精简 runtime 即可。

有网且坚持官方 SandboxFusion 时：独立 conda env `sandbox`（服务）+ `sandbox-runtime`（Python 3.10，名字必须这个）。训练 shell **禁止** `conda activate sandbox`。

## 代码与文档在哪

### Git（用户 fork，可拉到 Windows）

- 仓库：https://github.com/konfan12345678/verl
- 分支：`cursor/retool-windows-download-1916`
- PR：https://github.com/konfan12345678/verl/pull/1 （draft，仅投放 kit，不必强行合进 main）
- 目录：仓库根下 `retool/`（即用户要的 `C:\StudyMaterials\RL\verl\retool`）

Windows 有网时：

```powershell
cd C:\StudyMaterials\RL\verl
git fetch origin cursor/retool-windows-download-1916
git checkout origin/cursor/retool-windows-download-1916 -- retool
powershell -ExecutionPolicy Bypass -File .\retool\download_payload.ps1
```

若 `origin` 不是这个 fork：

```powershell
git remote add fork https://github.com/konfan12345678/verl.git
git fetch fork cursor/retool-windows-download-1916
git checkout fork/cursor/retool-windows-download-1916 -- retool
powershell -ExecutionPolicy Bypass -File .\retool\download_payload.ps1
```

国内：`$env:HF_ENDPOINT = "https://hf-mirror.com"`

`download_payload.ps1` 默认 Dest 就是 `C:\StudyMaterials\RL\verl\retool`，会写下 `retool\payload\`（CPython tar、两套 wheel、四个数据集 parquet）。**不含** 7B 权重。

Linux 跳板机等价：`bash retool/offline/download_on_jumphost.sh`（默认 `$HOME/retool-offline-payload`）。

### 上一次 Cloud Agent 里还有这些（新会话未必看得到大文件）

- Agent：https://cursor.com/agents/bc-bee3e742-b9be-50b1-b4c5-af5a04b01916
- Agent Store 文档：`/cursor/stores/bc-61d43390-fa92-428f-8840-76ef6f1a11c6/docs/`
  - `agentic-rl-retool/` 与 git `retool/` 同源
  - `verl-910b-vllm-images.md`、`verl-vllm-npu-ascend.md`、`verl-vllm-async-rollout.md`、`verl-vllm-async-rollout-versions.md`
- 458MB 预打包 tar 曾生成在云 VM：`/home/ubuntu/retool-910b-offline.tar.gz`（SHA256 `db9313366439512284c1ccbbf9bf5d4bdb59c884eaa1f453b0c1b9d135d28e5a`）
- **不要指望** Cursor 文件树 / Agent Store / Artifacts 下载这个 tar：Store 和 `/opt/cursor/artifacts` 写不进几百 MB；gitignored 的 tar 也不会出现在用户本机资源管理器。云 Agent **不能写入** `C:\`。

## 910B 内网容器流程（无网）

镜像建议 `--network host --ipc=host`，挂 driver。把 Windows 上下好的 `retool` 整目录挂进容器，例如 `/opt/retool`。

```bash
export KIT_ROOT=/opt/retool
export PAYLOAD_DIR=$KIT_ROOT/payload
export DATA_ROOT=$PAYLOAD_DIR/datasets
export VERL_ROOT=/workspace          # 容器里的 verl
export PYTHONPATH=$KIT_ROOT:$VERL_ROOT:$PYTHONPATH
export MODEL_PATH=/path/to/Qwen2.5-7B-Instruct

bash $KIT_ROOT/offline/install_on_intranet.sh
# 另开 tmux：用镜像 python3 起服务，--python 指向便携 3.10
python3 $KIT_ROOT/tools/local_run_code_server.py \
  --python $HOME/retool-offline/python/bin/python3
export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code

curl -fsS $SANDBOX_FUSION_URL -H 'Content-Type: application/json' \
  --data-raw '{"code":"import sympy; print(sympy.sqrt(4))","language":"python"}'
# 期望 stdout 含 2

source $KIT_ROOT/configs/env.npu.sh
pip install --no-deps -e $VERL_ROOT     # 对齐当前 main，勿动 vLLM

bash $KIT_ROOT/data/preprocess_sft.sh   # 写出 $DATA_ROOT/sft/train-00000-of-00001.parquet
bash $KIT_ROOT/scripts/run_sft_qwen25_7b_npu.sh
bash $KIT_ROOT/scripts/merge_sft_ckpt.sh <global_step_dir> <huggingface_dir>
export MODEL_PATH=<huggingface_dir>
bash $KIT_ROOT/scripts/run_grpo_qwen25_7b_npu.sh
```

NPU 环境变量（`configs/env.npu.sh`）：`RAY_EXPERIMENTAL_NOSET_ASCEND_RT_VISIBLE_DEVICES=1`，`ASCEND_RT_VISIBLE_DEVICES=0-7`，`VLLM_ASCEND_ENABLE_NZ=0`，`VLLM_USE_V1=1`，`TORCHDYNAMO_DISABLE=1`。

yaml：`recipe/retool/sandbox_fusion_tool_config.yaml`，`class_name=recipe.retool.retool.CustomSandboxFusionTool`，可用 `SANDBOX_FUSION_URL` 覆盖。共卡时把 yaml 里 `num_workers`/`rate_limit` 从 128 降到 16–32。

SFT 不需要沙箱；GRPO 必须沙箱先冒烟。控制台冷启动出现 `Failed to decode tool call` 可视为正常。

## 关键文件（相对 `retool/`）

- `download_payload.ps1` — Windows 拉 payload
- `offline/download_on_jumphost.sh` — Linux 拉 payload
- `offline/install_on_intranet.sh` — 解压便携 Python + 离线 pip
- `offline/URLS.md` — 浏览器直链
- `tools/local_run_code_server.py` — 兼容 `/run_code`
- `recipe/retool/retool.py` — CustomSandboxFusionTool + CustomRLHFDataset + compute_score
- `recipe/retool/sandbox_fusion_tools.py` — 从 verl 历史恢复的 HTTP 客户端
- `recipe/retool/retool_sft_preprocess.py` — ReTool-SFT → messages/tools parquet
- `scripts/run_*_npu.sh` — 910B SFT/GRPO
- `configs/env.npu.sh`

## 禁止

- 把 458MB tar 或 7B 权重 commit 进 git
- 在系统 Python 3.12 上 poetry/pip 装 SandboxFusion
- NPU 容器里装 CUDA vLLM
- 用 A3 镜像跑 910B
- 云 Agent 声称「已写入用户 C:\」——做不到；只能给脚本让用户在 Windows 上跑
- 为琐碎格式开新 PR；此 fork 上投放 kit 的 PR 已存在时不要再复制一份

## 还没做完 / 新会话可接着干

1. 用户是否已在 Windows 成功跑完 `download_payload.ps1`，`C:\StudyMaterials\RL\verl\retool\payload` 是否齐全
2. 7B 权重与训练镜像是否已单独下到内网（`huggingface-cli` / ModelScope / `docker save`）
3. 910B 上冒烟 `/run_code`、SFT、merge、GRPO
4. 不要无故重做镜像调研，除非用户换芯片或换 verl 大版本

## 回复风格

先给可执行下一步，再补背景。路径写绝对路径。改 verl 核心代码前先读仓库 `AGENTS.md`（禁止纯 agent 灌水 PR、重复 PR）。用户要的是把 ReTool 在 910B 内网跑通，不是把 kit 合进上游 verl main。

END PROMPT
