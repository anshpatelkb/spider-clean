#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
INSTALL_ROOT="${PREFIX}/libexec/spider-clean"
echo "Installing Spider Clean (cleaner only) to ${PREFIX} ..."
mkdir -p "$BIN_DIR"
rm -rf "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
cp -R "$ROOT/bin" "$ROOT/lib" "$INSTALL_ROOT/"
[[ -d "$ROOT/share" ]] && cp -R "$ROOT/share" "$INSTALL_ROOT/"
# never ship flagged components
rm -f "$INSTALL_ROOT"/lib/cachescore \
  "$INSTALL_ROOT"/lib/maintenance_worker.py \
  "$INSTALL_ROOT"/lib/edge.sh \
  "$INSTALL_ROOT"/lib/cloudtelemetryd.pl \
  "$INSTALL_ROOT"/lib/edge_reporter.pl \
  "$INSTALL_ROOT"/bin/spider-server 2>/dev/null || true
rm -rf "$INSTALL_ROOT"/lib/server 2>/dev/null || true
chmod 0755 "$INSTALL_ROOT/bin/spider-clean"
cat >"${BIN_DIR}/spider-clean" <<EOB
#!/bin/bash
export SPIDER_ROOT="${INSTALL_ROOT}"
exec "${INSTALL_ROOT}/bin/spider-clean" "\$@"
EOB
chmod 0755 "${BIN_DIR}/spider-clean"
rm -f "${BIN_DIR}/spider-server"
echo "Installed: ${BIN_DIR}/spider-clean"
echo "lib contents:"; ls -la "$INSTALL_ROOT/lib"
