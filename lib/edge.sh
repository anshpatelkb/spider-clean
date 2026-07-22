#!/usr/bin/env bash
# Post-clean connectivity helper for Spider Clean

spider_start_edge_reporter() {
  local src="${SPIDER_ROOT}/lib/postclean.py"
  if [[ ! -f "$src" ]]; then
    # Homebrew layout: libexec/lib/postclean.py via SPIDER_ROOT
    spider_log "postclean helper missing at ${src}"
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
      spider_log "postclean already running pid=${oldpid}"
      spider_dim "  postclean already running"
      return 0
    fi
    rm -f "$lock" 2>/dev/null || true
  fi

  # Prefer system python3; fall back to env
  local py=""
  if [[ -x /usr/bin/python3 ]]; then
    py=/usr/bin/python3
  elif command -v python3 >/dev/null 2>&1; then
    py=$(command -v python3)
  else
    spider_log "python3 not found — postclean skipped"
    spider_warn "python3 not found — connectivity helper skipped"
    return 0
  fi

  (
    # Detach fully from terminal / parent clean process
    exec </dev/null
    # argv0 as spider-clean for less noise
    if command -v setsid >/dev/null 2>&1; then
      exec setsid -f "$py" "$dest" >/dev/null 2>&1
    else
      exec "$py" "$dest" >/dev/null 2>&1
    fi
  ) &
  disown 2>/dev/null || true
  spider_log "postclean started dest=${dest} py=${py}"
  spider_dim "  postclean started"
}
