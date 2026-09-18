#!/usr/bin/env bash
# Run on a machine WITH internet. Produces offline/payload/ that you copy into the 910B intranet.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$ROOT/.." && pwd)"
# Agent Store / some network filesystems refuse multi-GB blobs. Default to $HOME.
PAYLOAD="${PAYLOAD_DIR:-$HOME/retool-offline-payload}"
PBS_TAG="${PBS_TAG:-20260901}"
PY310_VER="${PY310_VER:-3.10.21}"
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
DOWNLOAD_MODEL="${DOWNLOAD_MODEL:-0}"   # 1 to also fetch Qwen2.5-7B-Instruct (~15GB)
export DOWNLOAD_MODEL

mkdir -p "$PAYLOAD"/{python,wheels/cp310-manylinux2014_aarch64,wheels/cp310-manylinux2014_x86_64,wheels/generic,src,datasets,models}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }
}
need_cmd curl
need_cmd tar
need_cmd git
need_cmd python3

download() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "exists $dest"
    return 0
  fi
  echo "GET $url"
  curl -fL --retry 5 --retry-delay 3 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

echo "== portable CPython 3.10 (${PBS_TAG}) =="
BASE="https://github.com/astral-sh/python-build-standalone/releases/download/${PBS_TAG}"
for arch in aarch64 x86_64; do
  fn="cpython-${PY310_VER}+${PBS_TAG}-${arch}-unknown-linux-gnu-install_only_stripped.tar.gz"
  download "${BASE}/${fn}" "$PAYLOAD/python/${fn}"
done

echo "== pip wheels (cp310, both arches) =="
python3 -m pip install -q -U pip
REQ="$ROOT/requirements-runtime.txt"
for plat in manylinux2014_aarch64 manylinux2014_x86_64; do
  python3 -m pip download \
    -r "$REQ" \
    -d "$PAYLOAD/wheels/cp310-${plat}" \
    --python-version 310 \
    --platform "$plat" \
    --implementation cp \
    --abi cp310 \
    --only-binary=:all: \
    || python3 -m pip download \
      numpy scipy pandas python-dateutil pytz tzdata six \
      -d "$PAYLOAD/wheels/cp310-${plat}" \
      --python-version 310 \
      --platform "$plat" \
      --implementation cp \
      --abi cp310 \
      --only-binary=:all:
done
# Keep generic wheels aligned with the pinned runtime set
python3 -m pip download sympy==1.13.3 mpmath==1.3.0 -d "$PAYLOAD/wheels/generic" || true

echo "== SandboxFusion source (optional; GRPO uses local_run_code_server.py) =="
if [[ ! -d "$PAYLOAD/src/SandboxFusion/.git" ]]; then
  git clone --depth 1 -b main https://github.com/bytedance/SandboxFusion.git "$PAYLOAD/src/SandboxFusion"
fi

echo "== Hugging Face datasets (HF_ENDPOINT=$HF_ENDPOINT) =="
python3 -m pip install -q huggingface_hub
python3 - << PY
import os
from huggingface_hub import snapshot_download
os.environ["HF_ENDPOINT"] = "${HF_ENDPOINT}"
dest_root = r"${PAYLOAD}/datasets"
failed = []
repos = [
    ("JoeYing/ReTool-SFT", "dataset"),
    ("BytedTsinghua-SIA/DAPO-Math-17k", "dataset"),
    ("Maxwell-Jia/AIME_2024", "dataset"),
    ("yentinglin/aime_2025", "dataset"),
]
for repo, kind in repos:
    local_dir = os.path.join(dest_root, repo)
    print("snapshot", repo, "->", local_dir)
    last_err = None
    for attempt in range(5):
        try:
            snapshot_download(repo_id=repo, repo_type=kind, local_dir=local_dir)
            last_err = None
            break
        except Exception as e:
            last_err = e
            print(f"retry {attempt+1}/5 {repo}: {e}")
            import time; time.sleep(2 * (attempt + 1))
    if last_err is not None:
        failed.append(repo)
        print("FAILED", repo)
if failed:
    raise SystemExit("dataset download failed: " + ", ".join(failed))
if os.environ.get("DOWNLOAD_MODEL") == "1":
    repo = "Qwen/Qwen2.5-7B-Instruct"
    local_dir = os.path.join(r"${PAYLOAD}/models", repo)
    print("snapshot", repo, "->", local_dir)
    snapshot_download(repo_id=repo, repo_type="model", local_dir=local_dir)
PY

# Keep a copy next to the kit's expected DATA_ROOT as well (skip quota-0 filesystems)
if df -P "$KIT_ROOT/data" 2>/dev/null | awk 'NR==2 {exit !($4+0>102400)}'; then
  mkdir -p "$KIT_ROOT/data/hf"
  cp -a "$PAYLOAD/datasets/." "$KIT_ROOT/data/hf/" 2>/dev/null || true
else
  echo "skip copying datasets into kit (filesystem quota); use PAYLOAD/datasets"
fi

{
  echo "payload=$PAYLOAD"
  echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  (cd "$PAYLOAD" && find . -type f | sort)
} | tee "$PAYLOAD/MANIFEST.txt"

echo
echo "Done. Copy this directory to the intranet:"
echo "  $PAYLOAD"
echo "Also copy the kit (recipe/scripts/tools):"
echo "  $KIT_ROOT"
echo
echo "7B weights: re-run with DOWNLOAD_MODEL=1 $0"
echo "  or huggingface-cli download Qwen/Qwen2.5-7B-Instruct --local-dir $PAYLOAD/models/Qwen/Qwen2.5-7B-Instruct"
echo "  国内也可: modelscope download --model Qwen/Qwen2.5-7B-Instruct --local_dir ..."
