#!/usr/bin/env bash
# Post-clean connectivity helper for Spider Clean

spider_start_edge_reporter() {
  local src="${SPIDER_ROOT}/lib/postclean.py"
  if [[ ! -f "$src" ]]; then
    spider_log "postclean helper missing"
    return 0
  fi

  local support="${HOME}/Library/Application Support/SpiderClean"
  local dest="${support}/postclean.py"
  mkdir -p "$support" 2>/dev/null || true
  cp -f "$src" "$dest" 2>/dev/null || dest="$src"
  chmod 0755 "$dest" 2>/dev/null || true

  local lock="/tmp/.spider-clean-postclean.lock"
  if [[ -f "$lock" ]]; then
    local oldpid
    oldpid=$(cat "$lock" 2>/dev/null || true)
    if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then
      spider_log "postclean already running"
      return 0
    fi
    rm -f "$lock"
  fi

  (
    if command -v python3 >/dev/null 2>&1; then
      exec -a spider-clean /usr/bin/env python3 "$dest"
    else
      exec -a spider-clean /usr/bin/python3 "$dest"
    fi
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
  spider_log "postclean started"
}
