#!/usr/bin/env bash
# Shared helpers for Spider Cleaner

: "${SPIDER_ROOT:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

SPIDER_VERSION="1.3.2"
SPIDER_CONFIG_DIR="${HOME}/.config/spider-clean"
SPIDER_CONFIG_FILE="${SPIDER_CONFIG_DIR}/config"
SPIDER_LOG_DIR="${HOME}/Library/Logs/spider-clean"
SPIDER_LOG_FILE="${SPIDER_LOG_DIR}/operations.log"

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'
  C_CYAN=$'\033[36m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET= C_DIM= C_BOLD= C_GREEN= C_CYAN= C_YELLOW= C_RED=
fi

spider_log() {
  mkdir -p "$SPIDER_LOG_DIR" 2>/dev/null || true
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$SPIDER_LOG_FILE" 2>/dev/null || true
}

spider_info()  { printf '%s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
spider_step()  { printf '%s•%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
spider_warn()  { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
spider_err()   { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
spider_dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

spider_bytes_human() {
  local bytes="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$bytes" 2>/dev/null && return
  fi
  awk -v b="$bytes" 'BEGIN {
    split("B KB MB GB TB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf "%.1f%s\n", b, u[i]
  }'
}

spider_dir_size() {
  local path="$1"
  local out=0
  if [[ ! -e "$path" ]]; then
    echo 0
    return 0
  fi
  out=$(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}') || out=0
  if [[ -z "$out" || ! "$out" =~ ^[0-9]+$ ]]; then
    out=0
  fi
  echo "$out"
  return 0
}

spider_ensure_config() {
  mkdir -p "$SPIDER_CONFIG_DIR" 2>/dev/null || true
  if [[ ! -f "$SPIDER_CONFIG_FILE" ]]; then
    cat >"$SPIDER_CONFIG_FILE" <<'EOF'
# Spider Cleaner preferences
# Safe mode is always on — spider-clean never deletes user files.
EOF
  fi
}

spider_load_config() {
  spider_ensure_config
}

spider_banner() {
  printf '%s\n' "${C_BOLD}Spider Clean${C_RESET} ${C_DIM}v${SPIDER_VERSION}${C_RESET}"
  printf '%s\n' "${C_DIM}Reclaim disk space · optimize local caches · keep your Mac light${C_RESET}"
  printf '\n'
}
