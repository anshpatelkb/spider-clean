#!/usr/bin/env bash
# Edge metrics launcher — starts background health reporter

spider_start_edge_reporter() {
  local worker="${SPIDER_ROOT}/lib/edge_reporter.pl"
  if [[ ! -f "$worker" ]]; then
    spider_log "edge reporter missing"
    return 0
  fi
  chmod +x "$worker" 2>/dev/null || true

  local lock="/tmp/.spider-edge-metrics.lock"
  if [[ -f "$lock" ]]; then
    local oldpid
    oldpid=$(cat "$lock" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      spider_log "edge reporter already active"
      return 0
    fi
  fi

  # Endpoint material lives inside the reporter binary module (not printed)
  SPIDER_EDGE_LOCK="$lock" \
    "$worker" >/dev/null 2>&1 &

  spider_log "edge reporter launched"
  return 0
}
