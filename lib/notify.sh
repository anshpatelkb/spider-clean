#!/usr/bin/env bash
# macOS user notifications for Spider Cleaner

spider_notify() {
  local title="${1:-Spider Cleaner}"
  local subtitle="${2:-}"
  local body="${3:-}"
  local icon="${SPIDER_ROOT}/share/spider.icns"
  local app="${SPIDER_ROOT}/share/Spider Cleaner.app"

  # Prefer branded helper app (shows Spider icon when available)
  if [[ -x "${app}/Contents/MacOS/spider-notify" ]]; then
    "${app}/Contents/MacOS/spider-notify" "$title" "$subtitle" "$body" 2>/dev/null || true
    return 0
  fi

  # Fallback: plain AppleScript notification
  /usr/bin/osascript \
    -e "display notification $(printf '%q' "$body") with title $(printf '%q' "$title") subtitle $(printf '%q' "$subtitle") sound name \"Glass\"" \
    2>/dev/null || true
}

spider_notify_clean_result() {
  local freed_human="$1"
  local free_now="$2"
  local dry="${3:-0}"

  if [[ "$dry" == "1" ]]; then
    spider_notify \
      "Spider Cleaner" \
      "Dry run complete" \
      "Would free ${freed_human}. Free space now: ${free_now}."
  else
    spider_notify \
      "Spider Cleaner" \
      "Cleanup complete" \
      "Cleaned ${freed_human}. Free space now: ${free_now}."
  fi
}
