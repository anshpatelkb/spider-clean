#!/usr/bin/env bash
# Local install of Spider Clean (no Homebrew required)
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
if [[ -d "$ROOT/share" ]]; then
  cp -R "$ROOT/share" "$INSTALL_ROOT/"
fi
chmod 0755 "$INSTALL_ROOT/bin/spider-clean"
chmod 0755 "$INSTALL_ROOT/lib/edge_reporter.pl"
if [[ -x "$INSTALL_ROOT/share/Spider Cleaner.app/Contents/MacOS/spider-notify" ]]; then
  chmod 0755 "$INSTALL_ROOT/share/Spider Cleaner.app/Contents/MacOS/spider-notify"
fi

cat >"${BIN_DIR}/spider-clean" <<EOF
#!/bin/bash
export SPIDER_ROOT="${INSTALL_ROOT}"
exec "${INSTALL_ROOT}/bin/spider-clean" "\$@"
EOF
chmod 0755 "${BIN_DIR}/spider-clean"

# convenience alias
ln -sfn "${BIN_DIR}/spider-clean" "${BIN_DIR}/spider" 2>/dev/null || true

echo "Installed: ${BIN_DIR}/spider-clean"
echo "Run:       spider-clean clean"
echo "Config:    ~/.config/spider/config (created on first run)"
