# 跳板机手动下载地址（浏览器 / wget 均可）

把文件放到 `$HOME/retool-offline-payload/` 对应子目录，目录结构见 `OFFLINE.md`。

## 便携 CPython 3.10（必须，两个架构都下，内网按 uname -m 选用）

```
https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.10.21+20260901-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz
https://github.com/astral-sh/python-build-standalone/releases/download/20260901/cpython-3.10.21+20260901-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz
```

保存到：`payload/python/`

## 数学运行时 wheel（pip download，或按 requirements-runtime.txt）

在能上网且有 Python 的机器：

```bash
pip download -r requirements-runtime.txt \
  -d wheels/cp310-manylinux2014_aarch64 \
  --python-version 310 --platform manylinux2014_aarch64 \
  --implementation cp --abi cp310 --only-binary=:all:

pip download -r requirements-runtime.txt \
  -d wheels/cp310-manylinux2014_x86_64 \
  --python-version 310 --platform manylinux2014_x86_64 \
  --implementation cp --abi cp310 --only-binary=:all:
```

PyPI 直链示例（版本以 `requirements-runtime.txt` 为准）：

```
https://pypi.org/simple/numpy/
https://pypi.org/simple/scipy/
https://pypi.org/simple/pandas/
https://pypi.org/simple/sympy/
https://pypi.org/simple/mpmath/
```

选 **cp310 + manylinux2014_aarch64** 或 **manylinux2014_x86_64** 的 whl。

## 数据集（Hugging Face resolve）

```
https://huggingface.co/datasets/JoeYing/ReTool-SFT/resolve/main/train_2000.parquet
https://huggingface.co/datasets/BytedTsinghua-SIA/DAPO-Math-17k/resolve/main/data/dapo-math-17k.parquet
https://huggingface.co/datasets/Maxwell-Jia/AIME_2024/resolve/main/aime_2024_problems.parquet
https://huggingface.co/datasets/yentinglin/aime_2025/resolve/main/data/train-00000-of-00001-243207c6c994e1bd.parquet
```

镜像：把主机换成 `https://hf-mirror.com`。

保存到：

```
datasets/JoeYing/ReTool-SFT/train_2000.parquet
datasets/BytedTsinghua-SIA/DAPO-Math-17k/data/dapo-math-17k.parquet
datasets/Maxwell-Jia/AIME_2024/aime_2024_problems.parquet
datasets/yentinglin/aime_2025/data/train-00000-of-00001-243207c6c994e1bd.parquet
```

完整 snapshot 仍推荐：

```
huggingface-cli download JoeYing/ReTool-SFT --repo-type dataset --local-dir ...
```

## 基座模型 Qwen2.5-7B-Instruct（约 15GB，脚本默认不下）

```
https://huggingface.co/Qwen/Qwen2.5-7B-Instruct
https://www.modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct
```

```bash
huggingface-cli download Qwen/Qwen2.5-7B-Instruct --local-dir models/Qwen/Qwen2.5-7B-Instruct
# 或
modelscope download --model Qwen/Qwen2.5-7B-Instruct --local_dir models/Qwen/Qwen2.5-7B-Instruct
```

## 训练镜像（若内网仓库还没有）

```
quay.io/ascend/verl:latest-vllm-910b-ubuntu
# 国内可试: m.daocloud.io/quay.io/ascend/verl:latest-vllm-910b-ubuntu
docker save quay.io/ascend/verl:latest-vllm-910b-ubuntu | gzip > verl-latest-vllm-910b-ubuntu.tar.gz
```

## SandboxFusion 源码（可选备份，内网默认不用）

```
https://github.com/bytedance/SandboxFusion/archive/refs/heads/main.tar.gz
```
