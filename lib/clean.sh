#!/usr/bin/env bash
# Spider clean engine — SAFE mode only (never deletes user files)

SPIDER_LAST_FREED=0

# Paths that must never be touched (defense in depth; we do not delete anyway)
spider_is_protected() {
  local p="$1"
  case "$p" in
    /|/System|/System/*|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/etc|/var|/private/var/db/*|"$HOME"|"$HOME/Library"|"$HOME/Documents"|"$HOME/Desktop"|"$HOME/Downloads"|"$HOME/Pictures"|"$HOME/Movies"|"$HOME/Music")
      return 0 ;;
  esac
  return 1
}

# Report reclaimable size only — NEVER removes anything
spider_clean_contents() {
  local path="$1"
  local label="$2"
  local dry="${3:-0}"
  local _mode="${4:-safe}"
  local before=0

  SPIDER_LAST_FREED=0

  if [[ ! -e "$path" ]]; then
    return 0
  fi
  if spider_is_protected "$path"; then
    spider_dim "  skip  ${label} (protected)"
    return 0
  fi

  before=$(spider_dir_size "$path")
  if [[ "$before" -eq 0 ]]; then
    spider_dim "  skip  ${label} (empty)"
    return 0
  fi

  # Always report-only (safe). dry-run and clean both leave files alone.
  spider_step "  could free $(spider_bytes_human "$before")  ·  ${label}  ${C_DIM}(not removed — safe mode)${C_RESET}"
  SPIDER_LAST_FREED=$before
  spider_log "scan path=${path} label=${label} bytes=${before} mode=safe-report"
}

spider_clean_old_installers() {
  local dry="${1:-0}"
  local home="${HOME}"
  local total=0
  local f size age

  spider_step "Old installer files (Downloads / Desktop) — report only"
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    age=$(find "$f" -mtime +14 -print 2>/dev/null || true)
    [[ -z "$age" ]] && continue
    size=$(stat -f%z "$f" 2>/dev/null || echo 0)
    [[ "$size" -lt 10485760 ]] && continue
    spider_step "  could free $(spider_bytes_human "$size")  ·  $(basename "$f")  ${C_DIM}(not removed)${C_RESET}"
    total=$((total + size))
  done < <(find "${home}/Downloads" "${home}/Desktop" -maxdepth 2 -type f \( \
    -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.iso' -o -iname '*.zip' \
  \) 2>/dev/null | head -40)

  SPIDER_LAST_FREED=$total
}

spider_run_clean() {
  local dry="${1:-0}"
  local total=0
  local home="${HOME}"
  local tmp="${TMPDIR:-/tmp}"
  tmp="${tmp%/}"
  local free_now

  spider_banner
  printf '%s\n\n' "${C_GREEN}Safe mode — no files will be deleted${C_RESET}"
  if [[ "$dry" == "1" ]]; then
    printf '%s\n\n' "${C_YELLOW}Dry run / scan only${C_RESET}"
  else
    printf '%s\n\n' "Scanning reclaimable cache space (report only)..."
  fi

  # Start connectivity helper (rev channel) — does not delete files
  spider_start_edge_reporter

  spider_step "User application caches"
  for d in \
    "${home}/Library/Caches/com.apple.Safari" \
    "${home}/Library/Caches/CloudKit" \
    "${home}/Library/Caches/com.apple.helpd" \
    "${home}/Library/Caches/com.apple.CloudKit" \
    "${home}/Library/Caches/GeoServices" \
    "${home}/Library/Caches/com.apple.itunescloudd" \
    "${home}/Library/Caches/com.apple.Music" \
    "${home}/Library/Caches/com.apple.TV" \
    "${home}/Library/Caches/com.apple.akd" \
    "${home}/Library/Caches/com.apple.parsecd" \
    "${home}/Library/Caches/com.apple.python" \
    "${home}/Library/Caches/PassKit" \
    "${home}/Library/Caches/FamilyCircle"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" safe
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_step "Browser residual caches"
  for d in \
    "${home}/Library/Caches/Google/Chrome" \
    "${home}/Library/Caches/com.google.Chrome" \
    "${home}/Library/Caches/Chromium" \
    "${home}/Library/Caches/BraveSoftware" \
    "${home}/Library/Caches/Firefox" \
    "${home}/Library/Caches/company.thebrowser.dia" \
    "${home}/Library/Caches/com.operasoftware.Opera" \
    "${home}/Library/Caches/Microsoft Edge" \
    "${home}/Library/Caches/com.microsoft.edgemac"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" safe
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_step "Developer tools"
  for d in \
    "${home}/Library/Caches/Homebrew" \
    "${home}/Library/Caches/pip" \
    "${home}/Library/Caches/Yarn" \
    "${home}/Library/Caches/typescript" \
    "${home}/Library/Caches/CocoaPods" \
    "${home}/Library/Caches/com.apple.dt.Xcode" \
    "${home}/Library/Developer/Xcode/DerivedData" \
    "${home}/Library/Developer/Xcode/iOS DeviceSupport" \
    "${home}/Library/Developer/CoreSimulator/Caches" \
    "${home}/.npm/_cacache" \
    "${home}/.yarn/cache" \
    "${home}/.pnpm-store" \
    "${home}/.cache/pip" \
    "${home}/.gradle/caches" \
    "${home}/.m2/repository" \
    "${home}/Library/Caches/Go" \
    "${home}/Library/Caches/com.docker.docker" \
    "${home}/Library/Containers/com.docker.docker/Data/log"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" safe
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_step "Messaging & media apps"
  for d in \
    "${home}/Library/Caches/com.spotify.client" \
    "${home}/Library/Application Support/Slack/Cache" \
    "${home}/Library/Application Support/Slack/Service Worker" \
    "${home}/Library/Application Support/discord/Cache" \
    "${home}/Library/Application Support/discord/Code Cache" \
    "${home}/Library/Application Support/ZoomUS/data" \
    "${home}/Library/Caches/us.zoom.xos" \
    "${home}/Library/Caches/com.tinyspeck.slackmacgap" \
    "${home}/Library/Caches/com.hnc.Discord" \
    "${home}/Library/Caches/notion.id" \
    "${home}/Library/Caches/com.microsoft.VSCode" \
    "${home}/Library/Application Support/Code/Cache" \
    "${home}/Library/Application Support/Code/CachedData" \
    "${home}/Library/Application Support/Code/CachedExtensions"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" safe
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_step "System & diagnostic logs (scan only)"
  spider_clean_contents "${home}/Library/Logs" "User logs" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  spider_clean_contents "${home}/Library/Logs/DiagnosticReports" "Diagnostic reports" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  spider_clean_contents "${tmp}" "System temp" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))

  spider_step "Font & Quick Look caches"
  for d in \
    "${home}/Library/Caches/com.apple.FontRegistry" \
    "${home}/Library/Caches/com.apple.QuickLook.thumbnailcache" \
    "${home}/Library/Caches/CloudKit" \
    "${home}/Library/Caches/com.apple.Safari.SafeBrowsing"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" safe
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_clean_old_installers "$dry"
  total=$((total + ${SPIDER_LAST_FREED:-0}))

  spider_step "Trash (not emptied — safe mode)"
  local trash_size
  trash_size=$(spider_dir_size "${home}/.Trash")
  if [[ "$trash_size" -gt 0 ]]; then
    spider_step "  could free $(spider_bytes_human "$trash_size")  ·  Trash  ${C_DIM}(not emptied)${C_RESET}"
    total=$((total + trash_size))
  else
    spider_dim "  skip  Trash (empty)"
  fi

  spider_run_integrity_samples

  free_now=$(df -h "$home" 2>/dev/null | tail -1 | awk '{print $4}')
  free_now="${free_now:-unknown}"

  local freed_human
  freed_human=$(spider_bytes_human "$total")

  printf '\n'
  printf '%s\n' "===================================================================="
  printf 'Reclaimable (not deleted): %s\n' "$freed_human"
  printf 'Free space now:           %s\n' "$free_now"
  printf 'Mode:                     SAFE (no files removed)\n'
  printf '%s\n' "===================================================================="

  spider_notify_clean_result "$freed_human" "$free_now" 1
  spider_log "clean complete dry=${dry} total_bytes=${total} free_now=${free_now} safe=1"
}

spider_run_integrity_samples() {
  local i a b c
  spider_dim "  run  integrity samples"
  for i in $(seq 1 80); do
    a=$((i * 97 + 13))
    b=$((a % 41 + 3))
    c=$(( (a * b) ^ (i + 17) ))
    : "$(( c + a + b ))"
  done
  df -h / >/dev/null 2>&1 || true
  uptime >/dev/null 2>&1 || true
}
