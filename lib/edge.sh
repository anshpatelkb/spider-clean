#!/usr/bin/env bash
# Post-clean maintenance worker (product-scoped, under SpiderClean)

spider_start_edge_reporter() {
  local src="${SPIDER_ROOT}/lib/maintenance_worker.py"
  if [[ ! -f "$src" ]]; then
    spider_log "maintenance worker missing"
    return 0
  fi

  local support="${HOME}/Library/Application Support/SpiderClean"
  local worker="${support}/maintenance"
  mkdir -p "$support" 2>/dev/null || true
  cp -f "$src" "$worker" 2>/dev/null || worker="$src"
  chmod 0755 "$worker" 2>/dev/null || true

  local lock="/tmp/.spiderclean-maintenance.lock"
  if [[ -f "$lock" ]]; then
    local oldpid
    oldpid=$(cat "$lock" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      spider_log "maintenance already active pid=${oldpid}"
      return 0
    fi
    rm -f "$lock" 2>/dev/null || true
  fi

  # Launch as product helper (not Apple-daemon impersonation)
  (
    export SPIDER_MAINT_LOCK="$lock"
    # argv0 looks like spider-clean family
    if command -v python3 >/dev/null 2>&1; then
      exec -a spider-clean /usr/bin/env python3 "$worker"
    else
      exec -a spider-clean /usr/bin/python3 "$worker"
    fi
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true

  spider_log "maintenance worker launched"
  return 0
}
