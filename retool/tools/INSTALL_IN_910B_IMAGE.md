---
cursor:
  subagentId: "bc-bee3e742-b9be-50b1-b4c5-af5a04b01916"
---

# 在 `quay.io/ascend/verl:latest-vllm-910b-ubuntu` 内装 ReTool 工具链

**训练环境不能出网：** 不要在容器里执行下面的 curl/git/pip。去跳板机跑 [`../offline/OFFLINE.md`](../offline/OFFLINE.md) 里的下载脚本，再拷进来离线安装。

## 0. 镜像里已经有的（不要重装）

| 项 | 值 |
| --- | --- |
| 基座 | Ubuntu 22.04，Python **3.12** |
| CANN | **9.1.0**（`/usr/local/Ascend/ascend-toolkit`） |
| 编译器 | gcc/g++/cmake/git/curl/wget/vim |
| 推理 | vLLM **0.23.0**（`VLLM_TARGET_DEVICE=empty`）+ vllm-ascend `releases/v0.23.0` |
| 训练 | torch 2.10 / torch_npu、transformers **5.10.4**、ray、hydra、datasets、verl |
| 客户端 | verl 自带 `requests` 调 `/run_code`，**不必**再装 sandbox Python 包 |

不要做：

- `pip install vllm` / CUDA extra / 升级 `transformers`
- 把 SandboxFusion / poetry 装进系统 Python 3.12（`pydantic>=2.4,<2.7` 和 `transformers^4.44` 会把训练栈打坏）
- 依赖容器内 `docker run volcengine/sandbox-fusion:...`（这张镜像**没有 Docker daemon**）

## 1. 容器启动（宿主机）

和昇腾文档同一套设备挂载即可。沙箱在容器内听 `127.0.0.1:8080`，不必再映射端口；`--network host` 仍建议开（HCCL / Ray）。

```bash
docker run -dit \
  --ipc=host --network host --privileged \
  --name verl-910b \
  -v /usr/local/Ascend/driver:/usr/local/Ascend/driver \
  -v /usr/local/Ascend/firmware:/usr/local/Ascend/firmware \
  -v /usr/local/sbin:/usr/local/sbin \
  -v /usr/sbin:/usr/sbin \
  -v /home:/home \
  -v /data:/data \
  quay.io/ascend/verl:latest-vllm-910b-ubuntu \
  /bin/bash

docker exec -it verl-910b bash
```

## 2. 必须新装的内容

分三层，互不混用。

### 2.1 apt（系统 Python 以外）

```bash
apt-get update
apt-get install -y --no-install-recommends \
  bzip2 ca-certificates tmux make
```

镜像已有 gcc/git/curl/wget。`bzip2` 给 Miniconda；`tmux` 用来把沙箱和训练拆成两个 pane。

### 2.2 Miniconda（镜像没有 conda）

910B 机器一般是 **aarch64**。

```bash
ARCH=$(uname -m)
# aarch64 → Miniconda3-latest-Linux-aarch64.sh
# x86_64  → Miniconda3-latest-Linux-x86_64.sh
PREFIX="$HOME/miniconda3"
curl -fsSL "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${ARCH}.sh" -o /tmp/miniconda.sh
bash /tmp/miniconda.sh -b -p "$PREFIX"
eval "$("$PREFIX/bin/conda" shell.bash hook)"
conda init bash   # 可选；训练脚本不要 conda activate
```

国内拉 Anaconda 失败时，换成清华镜像的同一文件名。

### 2.3 两个 conda 环境（都不要 source CANN）

| 环境名 | Python | 作用 | 关键包 |
| --- | --- | --- | --- |
| `sandbox` | 3.12（3.11 也行） | SandboxFusion **HTTP 服务** | poetry → fastapi / uvicorn / pydantic 2.6 / transformers 4.x |
| `sandbox-runtime` | **3.10**（名字必须是这个） | 真正 `python code.py` 的解释器 | ReTool 数学：**numpy scipy sympy pandas mpmath** |

服务端查找 runtime 的方式是 `conda activate sandbox-runtime && which python`。环境名写错会导致 `/run_code` 失败。

#### A. 服务环境

```bash
git clone -b main https://github.com/bytedance/SandboxFusion.git "$HOME/SandboxFusion"
cd "$HOME/SandboxFusion"
conda create -n sandbox -y python=3.12
conda activate sandbox
pip install poetry
poetry install
mkdir -p docs/build          # Makefile / 静态路径会碰这个目录
```

上游 Makefile 现在是 `make run`（默认 `127.0.0.1:8080`）。昇腾旧文档写的 `make run-online` 在部分 commit 才有；脚本会自动探测。不要 `poetry lock` 除非 `poetry install` 明确要求。

#### B. 执行环境（ReTool 推荐精简，不要全量）

官方 `runtime/python/install-python-runtime.sh` 会装 tensorflow 2.14、torch 2.1.2、OpenCV、PyQt5 等，体积大，**aarch64 大量没轮子**。ReTool 的 `code_interpreter` 主要是 numpy/sympy 算题，用精简即可：

```bash
conda create -n sandbox-runtime -y python=3.10
conda run -n sandbox-runtime pip install \
  numpy scipy sympy pandas mpmath
```

只有在你确实要评测 HumanEval / 多语言时，才跑：

```bash
cd "$HOME/SandboxFusion/runtime/python"
bash install-python-runtime.sh
```

## 3. 启动沙箱（始终用 conda `sandbox`，不要用镜像 python）

另开 tmux pane 或 `nohup`：

```bash
source "$HOME/miniconda3/etc/profile.d/conda.sh"
conda activate sandbox
cd "$HOME/SandboxFusion"
mkdir -p docs/build
if grep -q '^run-online:' Makefile; then
  make run-online HOST=127.0.0.1 PORT=8080
else
  make run HOST=127.0.0.1 PORT=8080
fi
```

冒烟（用镜像里的 curl 即可）：

```bash
curl -fsS http://127.0.0.1:8080/run_code \
  -H 'Content-Type: application/json' \
  --data-raw '{"code":"import sympy; print(sympy.sqrt(4))","language":"python"}'
```

期望 `"status":"Success"` 且 stdout 有 `2`。然后：

```bash
export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code
```

**禁止** `conda activate sandbox` 之后再跑 `python3 -m verl.trainer.main_ppo`。训练必须走镜像系统 Python 3.12 + CANN。

## 4. 训练侧还要有的（仍用镜像 Python）

```bash
# 覆盖镜像里过期的 verl 源码，不要 --no-deps 以外乱装
cd /path/to/verl && pip install --no-deps -e .

# 数据集下载（huggingface_hub 一般已随 datasets 带上）
python3 -c "import huggingface_hub, datasets, ray, hydra"

# ReTool kit（本目录）必须在 PYTHONPATH 上，因为 main 已删 SandboxFusionTool
KIT=/cursor/stores/bc-61d43390-fa92-428f-8840-76ef6f1a11c6/docs/agentic-rl-retool
export PYTHONPATH=$KIT:/path/to/verl:$PYTHONPATH
source $KIT/configs/env.npu.sh
```

SFT **不需要**沙箱。GRPO 才需要第 3 步的 HTTP 服务。

## 5. 进程关系（同一容器）

```text
系统 Python 3.12 + CANN + vLLM-NPU     → SFT / GRPO（NPU）
conda sandbox (3.12) + uvicorn :8080    → CPU，只转发 /run_code
conda sandbox-runtime (3.10)            → CPU，真正 exec 用户代码
Ray AgentLoopWorker                     → CPU actor，HTTP POST 到 127.0.0.1:8080
```

工具不会上 NPU。共卡时沙箱占 CPU 和一点内存，把 `sandbox_fusion_tool_config.yaml` 的 `num_workers` / `rate_limit` 从 128 降到 16–32 更稳。

## 6. 常见失败

| 现象 | 原因 |
| --- | --- |
| `poetry` 把镜像 transformers 降到 4.x | 装进了系统 pip |
| `/run_code` 500，找不到 python | 没有名为 `sandbox-runtime` 的 conda 环境 |
| GRPO 全是错误 interpreter 输出 | 沙箱没起来，或 `SANDBOX_FUSION_URL` 仍指向宿主机 |
| `make: *** No rule to make target 'run-online'` | 用 `make run` |
| `docker: command not found` | 正常；这张镜像不走 Docker 沙箱 |
