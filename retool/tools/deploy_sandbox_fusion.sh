#!/usr/bin/env bash
# Deploy ByteDance SandboxFusion as the code_interpreter backend.
set -euo pipefail

MODE="${1:-docker}"
PORT="${SANDBOX_PORT:-8080}"
IMAGE="${SANDBOX_IMAGE:-volcengine/sandbox-fusion:server-20250609}"

smoke() {
  echo "Probing http://127.0.0.1:${PORT}/run_code ..."
  curl -fsS "http://127.0.0.1:${PORT}/run_code" \
    -H "Content-Type: application/json" \
    --data-raw '{"code":"print(1+1)","language":"python"}'
  echo
}

case "$MODE" in
  docker)
    echo "Pulling $IMAGE"
    docker pull "$IMAGE"
    docker rm -f sandbox-fusion >/dev/null 2>&1 || true
    docker run -d --name sandbox-fusion --restart unless-stopped \
      --privileged -p "${PORT}:8080" "$IMAGE"
    sleep 5
    smoke
    echo "SANDBOX_FUSION_URL=http://127.0.0.1:${PORT}/run_code"
    ;;
  source)
    ROOT="${SANDBOX_SRC:-$HOME/SandboxFusion}"
    if [[ ! -d "$ROOT" ]]; then
      git clone -b main https://github.com/bytedance/SandboxFusion.git "$ROOT"
    fi
    cd "$ROOT"
    conda create -n sandbox -y python=3.11 || true
    # shellcheck disable=SC1091
    source "$(conda info --base)/etc/profile.d/conda.sh"
    conda activate sandbox
    pip install poetry
    poetry install
    mkdir -p docs/build
    if [[ -d runtime/python ]]; then
      (cd runtime/python && bash install-python-runtime.sh)
    fi
    make run-online
    ;;
  smoke)
    smoke
    ;;
  *)
    echo "Usage: $0 [docker|source|smoke]" >&2
    echo "Inside quay.io/ascend/verl:latest-vllm-910b-ubuntu use install_in_910b_image.sh instead." >&2
    exit 2
    ;;
esac
