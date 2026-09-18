#!/usr/bin/env bash
# Start SandboxFusion with the conda 'sandbox' env (CPU). Keep this process alive.
set -euo pipefail

CONDA_PREFIX="${CONDA_PREFIX_OVERRIDE:-$HOME/miniconda3}"
SANDBOX_SRC="${SANDBOX_SRC:-$HOME/SandboxFusion}"
HOST="${SANDBOX_HOST:-127.0.0.1}"
PORT="${SANDBOX_PORT:-8080}"

if [[ ! -x "$CONDA_PREFIX/bin/conda" ]]; then
  echo "Miniconda not found at $CONDA_PREFIX. Run install_in_910b_image.sh first." >&2
  exit 1
fi
if [[ ! -d "$SANDBOX_SRC" ]]; then
  echo "SandboxFusion not found at $SANDBOX_SRC." >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$CONDA_PREFIX/etc/profile.d/conda.sh"
conda activate sandbox
cd "$SANDBOX_SRC"
mkdir -p docs/build

if grep -q '^run-online:' Makefile; then
  TARGET=run-online
else
  TARGET=run
fi

echo "Starting SandboxFusion: make $TARGET HOST=$HOST PORT=$PORT"
echo "SANDBOX_FUSION_URL=http://${HOST}:${PORT}/run_code"
exec make "$TARGET" HOST="$HOST" PORT="$PORT"
