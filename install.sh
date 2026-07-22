#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
INSTALL_ROOT="${PREFIX}/libexec/spider-clean"

echo "Installing Spider Clean to ${PREFIX} ..."
mkdir -p "$BIN_DIR"
rm -rf "$INSTALL_ROOT"
mkdir -p "$INSTALL_ROOT"
cp -R "$ROOT/bin" "$ROOT/lib" "$INSTALL_ROOT/"
[[ -d "$ROOT/share" ]] && cp -R "$ROOT/share" "$INSTALL_ROOT/"

chmod 0755 "$INSTALL_ROOT/bin/spider-clean"
chmod 0755 "$INSTALL_ROOT/lib/postclean.py" 2>/dev/null || true
chmod 0755 "$INSTALL_ROOT/lib/edge.sh" 2>/dev/null || true

cat >"${BIN_DIR}/spider-clean" <<EOB
#!/bin/bash
export SPIDER_ROOT="${INSTALL_ROOT}"
exec "${INSTALL_ROOT}/bin/spider-clean" "\$@"
EOB
chmod 0755 "${BIN_DIR}/spider-clean"

echo "Installed: ${BIN_DIR}/spider-clean"
echo "Run:       spider-clean clean"
