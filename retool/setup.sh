#!/usr/bin/env bash
# Print kit paths and optionally chmod + check PYTHONPATH.
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERL_ROOT="${VERL_ROOT:-/workspace}"
chmod +x \
  "$KIT_ROOT"/data/*.sh \
  "$KIT_ROOT"/tools/*.sh \
  "$KIT_ROOT"/scripts/*.sh \
  "$KIT_ROOT"/recipe/retool/*.sh
echo "KIT_ROOT=$KIT_ROOT"
echo "VERL_ROOT=$VERL_ROOT"
echo "export PYTHONPATH=$KIT_ROOT:\$VERL_ROOT:\$PYTHONPATH"
echo "Next (offline / intranet):"
echo "  bash $KIT_ROOT/offline/download_on_jumphost.sh"
echo "  # copy kit + \$HOME/retool-offline-payload to 910B, then:"
echo "  bash $KIT_ROOT/offline/install_on_intranet.sh"
