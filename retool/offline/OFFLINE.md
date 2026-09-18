---
cursor:
  subagentId: "bc-bee3e742-b9be-50b1-b4c5-af5a04b01916"
---

# 内网 910B：先在能上网的机器下载，再拷进去

训练机走 `quay.io/ascend/verl:latest-vllm-910b-ubuntu` 且**不能出网**时，不要在容器里 `git clone` / `pip install` / `huggingface-cli download`。

流程是：

1. 在一台能访问 GitHub / Hugging Face（或 hf-mirror / ModelScope）的机器上跑下载脚本
2. 把整个 kit + `offline/payload/` 拷到 910B（scp / 网盘 / 移动盘）
3. 在 910B 容器里跑离线安装脚本，用便携 CPython 3.10 起兼容 `/run_code` 的本地沙箱

本环境若已经跑过下载，payload 默认在跳板机的：

`$HOME/retool-offline-payload`

（不要写进 Agent Store / 部分网盘；那些盘对大文件会 `No space left`。）

把 **整个 kit 目录** 和 **payload 目录** 一起拷到内网。

## 1. 能上网的机器：下什么

```bash
KIT=.../docs/agentic-rl-retool          # 本工具包根目录
# 产物默认: $HOME/retool-offline-payload  （可用 PAYLOAD_DIR=... 改路径）
bash $KIT/offline/download_on_jumphost.sh
```

默认拉这些（体积大约 **0.5–2 GB**，不含 7B 权重）：

| 路径（相对 `$HOME/retool-offline-payload/`） | 内容 | 用途 |
| --- | --- | --- |
| `python/cpython-3.10.21+20260901-{aarch64,x86_64}-unknown-linux-gnu-install_only_stripped.tar.gz` | 便携 CPython 3.10 | 真正执行模型写的 Python |
| `wheels/cp310-manylinux2014_aarch64/` | numpy/scipy/pandas 等 **ARM64** 轮子 | 910B 常见 Kunpeng/aarch64 |
| `wheels/cp310-manylinux2014_x86_64/` | 同上 **x86_64** | 部分 x86 主机 + 910B 卡 |
| `wheels/generic/` | sympy、mpmath（纯 Python） | 数学表达式 |
| `src/SandboxFusion/` | 上游沙箱源码（备份） | 内网一般**不用**再 poetry 装 |
| `datasets/JoeYing/ReTool-SFT` | SFT 轨迹 | 冷启动 |
| `datasets/BytedTsinghua-SIA/DAPO-Math-17k` | GRPO 训练 | 多轮工具 RL |
| `datasets/Maxwell-Jia/AIME_2024` | GRPO 验证 | 910B 脚本默认 val |
| `datasets/yentinglin/aime_2025` | GRPO 验证 | 论文指标 |

**基座权重默认不下**（Qwen2.5-7B-Instruct 约 15GB）。需要时：

```bash
# Hugging Face
DOWNLOAD_MODEL=1 bash $KIT/offline/download_on_jumphost.sh

# 或单独：
huggingface-cli download Qwen/Qwen2.5-7B-Instruct \
  --local-dir $KIT/offline/payload/models/Qwen/Qwen2.5-7B-Instruct

# 国内 ModelScope（内网跳板常见）
pip install modelscope
modelscope download --model Qwen/Qwen2.5-7B-Instruct \
  --local_dir $KIT/offline/payload/models/Qwen/Qwen2.5-7B-Instruct
```

GitHub / HF 被墙时，在跳板机先设：

```bash
export HF_ENDPOINT=https://hf-mirror.com
export GIT_SSL_NO_VERIFY=1   # 仅当公司代理证书有问题时
bash $KIT/offline/download_on_jumphost.sh
```

便携 Python 的直链（可浏览器/wget 另存）：

```text
https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.10.21+20260901-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz
https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.10.21+20260901-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz
```

数据集直链（浏览器也可）：

```text
https://huggingface.co/datasets/JoeYing/ReTool-SFT
https://huggingface.co/datasets/BytedTsinghua-SIA/DAPO-Math-17k
https://huggingface.co/datasets/Maxwell-Jia/AIME_2024
https://huggingface.co/datasets/yentinglin/aime_2025
https://huggingface.co/Qwen/Qwen2.5-7B-Instruct
```

**不要下、也不要拷进训练容器的：**

- CUDA 版 vLLM wheel
- SandboxFusion 官方 `volcengine/sandbox-fusion` Docker 镜像（910B 训练镜像里没有 dockerd）
- `runtime/python/install-python-runtime.sh` 全量（tensorflow/torch/PyQt，aarch64 基本装不上）

训练镜像 `quay.io/ascend/verl:latest-vllm-910b-ubuntu` 假定内网镜像仓库里**已经有**。若没有，在能出网的机器：

```bash
docker pull quay.io/ascend/verl:latest-vllm-910b-ubuntu
docker save quay.io/ascend/verl:latest-vllm-910b-ubuntu | gzip > verl-latest-vllm-910b-ubuntu.tar.gz
# 内网: gunzip -c verl-latest-vllm-910b-ubuntu.tar.gz | docker load
```

## 2. 怎么拷到内网

整包一起走（保留目录结构）：

```bash
# 跳板机打包两样：kit（脚本小）+ payload（安装包/数据）
tar -cvf retool-kit.tar -C "$(dirname $KIT)" "$(basename $KIT)"
tar -cvf retool-payload.tar -C "$HOME" retool-offline-payload
# scp / 网盘 / 移动盘拷到 910B 后:
#   tar -xvf retool-kit.tar && tar -xvf retool-payload.tar
```

放到 910B 宿主机后挂进容器，例如 `-v /data/retool-kit:/opt/retool-kit`。

核对：`offline/payload/MANIFEST.txt` 应列出 python 两个 tar、两套 wheels、四个数据集目录。

## 3. 内网容器里（无网）

```bash
KIT=/opt/retool-kit
export PAYLOAD_DIR=$HOME/retool-offline-payload   # 或你解压后的路径
export DATA_ROOT=$PAYLOAD_DIR/datasets
export MODEL_PATH=$PAYLOAD_DIR/models/Qwen/Qwen2.5-7B-Instruct   # 若已拷权重
export VERL_ROOT=/workspace                                     # 容器里的 verl
export PYTHONPATH=$KIT:$VERL_ROOT:$PYTHONPATH

bash $KIT/offline/install_on_intranet.sh

# 另开 tmux/shell，保持前台
export SANDBOX_RUNTIME_PYTHON=$HOME/retool-offline/python/bin/python3
python3 $KIT/tools/local_run_code_server.py --python $SANDBOX_RUNTIME_PYTHON
export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code

curl -fsS $SANDBOX_FUSION_URL -H 'Content-Type: application/json' \
  --data-raw '{"code":"import sympy; print(sympy.sqrt(4))","language":"python"}'
```

SFT 预处理（镜像里已有 `datasets` / `omegaconf`，仍不需要出网）：

```bash
bash $KIT/data/preprocess_sft.sh \
  $DATA_ROOT/JoeYing/ReTool-SFT \
  $DATA_ROOT/sft/train-00000-of-00001.parquet
```

然后照常 `bash $KIT/scripts/run_sft_qwen25_7b_npu.sh` / `run_grpo_qwen25_7b_npu.sh`。

本地沙箱只实现 **Python** `/run_code`，JSON 字段与 SandboxFusion 一致，ReTool 的 `CustomSandboxFusionTool` 不用改。

## 4. 架构注意

910B 可能是 **aarch64** 也可能是 **x86_64 + NPU**。跳板机是 x86 没关系，脚本两种 wheel 都下。内网安装脚本按 `uname -m` 选对应 tar 和 wheel 目录。**不要**在 x86 跳板机 `pip install` 出环境再原样拷到 aarch64。
