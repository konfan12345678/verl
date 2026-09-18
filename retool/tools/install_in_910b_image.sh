#!/usr/bin/env bash
# Install SandboxFusion inside quay.io/ascend/verl:latest-vllm-910b-ubuntu.
# Does NOT touch the image's system Python 3.12 / vLLM / transformers.
set -euo pipefail

RUNTIME_MODE="${1:-slim}"   # slim | full
CONDA_PREFIX="${CONDA_PREFIX_OVERRIDE:-$HOME/miniconda3}"
SANDBOX_SRC="${SANDBOX_SRC:-$HOME/SandboxFusion}"
SANDBOX_PY="${SANDBOX_PY:-3.12}"

if [[ "$RUNTIME_MODE" != "slim" && "$RUNTIME_MODE" != "full" ]]; then
  echo "Usage: $0 [slim|full]" >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends bzip2 ca-certificates tmux make

if [[ ! -x "$CONDA_PREFIX/bin/conda" ]]; then
  ARCH="$(uname -m)"
  INSTALLER="/tmp/miniconda.sh"
  URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-${ARCH}.sh"
  echo "Installing Miniconda to $CONDA_PREFIX from $URL"
  curl -fsSL "$URL" -o "$INSTALLER"
  bash "$INSTALLER" -b -p "$CONDA_PREFIX"
  rm -f "$INSTALLER"
fi

# shellcheck disable=SC1091
source "$CONDA_PREFIX/etc/profile.d/conda.sh"

if [[ ! -d "$SANDBOX_SRC/.git" ]]; then
  git clone -b main https://github.com/bytedance/SandboxFusion.git "$SANDBOX_SRC"
fi

conda create -n sandbox -y "python=${SANDBOX_PY}" 2>/dev/null || true
conda activate sandbox
python -m pip install -U pip
python -m pip install poetry
(
  cd "$SANDBOX_SRC"
  poetry install
  mkdir -p docs/build
)

if [[ "$RUNTIME_MODE" == "full" ]]; then
  (
    cd "$SANDBOX_SRC/runtime/python"
    bash install-python-runtime.sh
  )
else
  conda create -n sandbox-runtime -y python=3.10 2>/dev/null || true
  conda run -n sandbox-runtime python -m pip install -U pip
  conda run -n sandbox-runtime python -m pip install numpy scipy sympy pandas mpmath
fi

conda deactivate || true

echo
echo "Installed:"
echo "  conda:            $CONDA_PREFIX"
echo "  SandboxFusion:    $SANDBOX_SRC"
echo "  server env:       sandbox (python ${SANDBOX_PY})"
echo "  exec env:         sandbox-runtime (python 3.10, mode=$RUNTIME_MODE)"
echo
echo "Next: bash $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/start_sandbox_in_image.sh"
echo "Then: export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code"
echo "Do NOT conda activate sandbox in the training shell."
