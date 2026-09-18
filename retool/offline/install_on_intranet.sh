#!/usr/bin/env bash
# Run INSIDE quay.io/ascend/verl:latest-vllm-910b-ubuntu on the intranet.
# No network. Unpacks portable CPython 3.10, installs math wheels, starts /run_code.
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="${PAYLOAD_DIR:-$HOME/retool-offline-payload}"
PREFIX="${SANDBOX_PREFIX:-$HOME/retool-offline}"
HOST="${SANDBOX_HOST:-127.0.0.1}"
PORT="${SANDBOX_PORT:-8080}"
START="${START_SERVER:-0}"

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) PLAT=aarch64 ; PIP_PLAT=manylinux2014_aarch64 ;;
  x86_64|amd64)  PLAT=x86_64  ; PIP_PLAT=manylinux2014_x86_64 ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

TAR=$(ls "$PAYLOAD/python"/cpython-3.10.*-"${PLAT}"-unknown-linux-gnu-install_only_stripped.tar.gz 2>/dev/null | head -1 || true)
[[ -f "$TAR" ]] || { echo "missing portable python tarball for $PLAT under $PAYLOAD/python" >&2; exit 1; }

mkdir -p "$PREFIX"
if [[ ! -x "$PREFIX/python/bin/python3" ]]; then
  echo "Extracting $TAR"
  tar -xzf "$TAR" -C "$PREFIX"
fi
PY="$PREFIX/python/bin/python3"
[[ -x "$PY" ]] || { echo "extract did not produce $PY" >&2; exit 1; }

WHEEL_DIR="$PAYLOAD/wheels/cp310-${PIP_PLAT}"
GEN_DIR="$PAYLOAD/wheels/generic"
"$PY" -m pip install --no-index --find-links "$WHEEL_DIR" --find-links "$GEN_DIR" \
  numpy scipy pandas sympy mpmath

# Datasets stay in payload; do not copy onto quota-limited kit filesystems.
export SANDBOX_RUNTIME_PYTHON="$PY"
export SANDBOX_FUSION_URL="http://${HOST}:${PORT}/run_code"
echo "SANDBOX_RUNTIME_PYTHON=$SANDBOX_RUNTIME_PYTHON"
echo "SANDBOX_FUSION_URL=$SANDBOX_FUSION_URL"
echo "DATA_ROOT=${DATA_ROOT:-$PAYLOAD/datasets}"

if [[ "$START" == "1" ]]; then
  exec python3 "$KIT_ROOT/tools/local_run_code_server.py" \
    --host "$HOST" --port "$PORT" --python "$PY"
fi

echo
echo "Start the sandbox in another shell (keep it running):"
echo "  python3 $KIT_ROOT/tools/local_run_code_server.py --python $PY --host $HOST --port $PORT"
echo "Smoke:"
echo "  curl -fsS \$SANDBOX_FUSION_URL -H 'Content-Type: application/json' --data-raw '{\"code\":\"import sympy; print(sympy.sqrt(4))\",\"language\":\"python\"}'"
