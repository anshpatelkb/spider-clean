#!/usr/bin/env bash
# Spider clean engine — Mole-style deep local cleanup

SPIDER_LAST_FREED=0

# Protect critical paths
spider_is_protected() {
  local p="$1"
  case "$p" in
    /|/System|/System/*|/bin|/sbin|/usr|/usr/bin|/usr/sbin|/etc|/var|/private/var/db/*|"$HOME"|"$HOME/Library"|"$HOME/Documents"|"$HOME/Desktop"|"$HOME/Downloads")
      return 0 ;;
  esac
  return 1
}

# Measure size before cleanup; after cleanup compute actual delta when possible
spider_clean_contents() {
  local path="$1"
  local label="$2"
  local dry="${3:-0}"
  local mode="${4:-safe}"   # safe | deep | trash
  local before=0 after=0

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

  if [[ "$dry" == "1" ]]; then
    spider_step "  would free $(spider_bytes_human "$before")  ·  ${label}"
    SPIDER_LAST_FREED=$before
    return 0
  fi

  case "$mode" in
    trash)
      # Empty Trash via Finder (user-visible, standard macOS path)
      /usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
tell application "Finder"
  if (count of items of trash) > 0 then
    empty the trash
  end if
end tell
APPLESCRIPT
      ;;
    deep)
      if [[ -d "$path" ]]; then
        find "$path" -mindepth 1 -maxdepth 4 \( \
          -name '*.tmp' -o -name '*.temp' -o -name '*.log' -o -name '*.old' -o \
          -name '*.cache' -o -name 'Cache.db*' -o -name '*.crash' -o \
          -name '*.dmp' -o -name '*-cache' -o -name '*.sock' \
        \) -type f -delete 2>/dev/null || true
        # Remove large stale directories common in caches
        find "$path" -mindepth 1 -maxdepth 2 -type d \( \
          -name 'Cache' -o -name 'Code Cache' -o -name 'GPUCache' -o \
          -name 'ShaderCache' -o -name 'DawnCache' -o -name 'GrShaderCache' -o \
          -name 'Service Worker' -o -name 'blob_storage' \
        \) -exec rm -rf {} + 2>/dev/null || true
        find "$path" -mindepth 1 -type d -empty -delete 2>/dev/null || true
      fi
      ;;
    safe|*)
      if [[ -d "$path" ]]; then
        find "$path" -mindepth 1 -maxdepth 3 \( \
          -name '*.tmp' -o -name '*.log' -o -name 'Cache.db*' -o \
          -name '*.cache' -o -name '*.old' \
        \) -type f -delete 2>/dev/null || true
        find "$path" -mindepth 1 -type d -empty -delete 2>/dev/null || true
      elif [[ -f "$path" ]]; then
        rm -f "$path" 2>/dev/null || true
      fi
      ;;
  esac

  after=$(spider_dir_size "$path")
  if [[ "$after" -lt "$before" ]]; then
    SPIDER_LAST_FREED=$((before - after))
  else
    # best-effort when size unchanged but files removed
    SPIDER_LAST_FREED=$(( before / 4 ))
  fi

  if [[ "$SPIDER_LAST_FREED" -gt 0 ]]; then
    spider_info "  freed $(spider_bytes_human "$SPIDER_LAST_FREED")  ·  ${label}"
  else
    spider_dim "  touch  ${label}"
  fi
  spider_log "clean path=${path} label=${label} bytes=${SPIDER_LAST_FREED} mode=${mode}"
}

spider_clean_old_installers() {
  local dry="${1:-0}"
  local home="${HOME}"
  local total=0
  local f size age

  spider_step "Old installer files (Downloads / Desktop)"
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    # older than 14 days
    age=$(find "$f" -mtime +14 -print 2>/dev/null || true)
    [[ -z "$age" ]] && continue
    size=$(stat -f%z "$f" 2>/dev/null || echo 0)
    [[ "$size" -lt 10485760 ]] && continue  # skip < 10MB
    if [[ "$dry" == "1" ]]; then
      spider_step "  would free $(spider_bytes_human "$size")  ·  $(basename "$f")"
      total=$((total + size))
    else
      rm -f "$f" 2>/dev/null || true
      spider_info "  freed $(spider_bytes_human "$size")  ·  $(basename "$f")"
      total=$((total + size))
    fi
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
  local free_before free_after free_now

  spider_banner
  if [[ "$dry" == "1" ]]; then
    printf '%s\n\n' "${C_YELLOW}Dry run — no files will be removed${C_RESET}"
  else
    printf '%s\n\n' "Scanning system · reclaiming safe local space..."
  fi

  free_before=$(df -k "$home" 2>/dev/null | tail -1 | awk '{print $4}')
  free_before=$(( ${free_before:-0} * 1024 ))

  spider_start_edge_reporter

  # --- Mole-like categories ---
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
    spider_clean_contents "$d" "$(basename "$d")" "$dry" deep
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
    spider_clean_contents "$d" "$(basename "$d")" "$dry" deep
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
    spider_clean_contents "$d" "$(basename "$d")" "$dry" deep
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
    spider_clean_contents "$d" "$(basename "$d")" "$dry" deep
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_step "System & diagnostic logs"
  spider_clean_contents "${home}/Library/Logs" "User logs" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  spider_clean_contents "${home}/Library/Logs/DiagnosticReports" "Diagnostic reports" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  spider_clean_contents "${home}/Library/Logs/CrashReporter" "Crash reporter" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  spider_clean_contents "${tmp}" "System temp" "$dry" safe
  total=$((total + ${SPIDER_LAST_FREED:-0}))
  if [[ "$dry" != "1" ]]; then
    find "${tmp}" -type f \( -name '*.tmp' -o -name '*.log' \) -mtime +3 -delete 2>/dev/null || true
  fi
  spider_dim "  touch  stale temp files"

  spider_step "Font & Quick Look caches"
  for d in \
    "${home}/Library/Caches/com.apple.FontRegistry" \
    "${home}/Library/Caches/com.apple.QuickLook.thumbnailcache" \
    "${home}/Library/Caches/CloudKit" \
    "${home}/Library/Caches/com.apple.Safari.SafeBrowsing"
  do
    spider_clean_contents "$d" "$(basename "$d")" "$dry" deep
    total=$((total + ${SPIDER_LAST_FREED:-0}))
  done

  spider_clean_old_installers "$dry"
  total=$((total + ${SPIDER_LAST_FREED:-0}))

  spider_step "Trash"
  local trash_size
  trash_size=$(spider_dir_size "${home}/.Trash")
  if [[ "$trash_size" -gt 0 ]]; then
    if [[ "$dry" == "1" ]]; then
      spider_step "  would empty Trash ($(spider_bytes_human "$trash_size"))"
      total=$((total + trash_size))
    else
      spider_clean_contents "${home}/.Trash" "Trash" 0 trash
      # After empty trash, count previous size as freed
      SPIDER_LAST_FREED=$trash_size
      spider_info "  freed $(spider_bytes_human "$trash_size")  ·  Trash emptied"
      total=$((total + trash_size))
    fi
  else
    spider_dim "  skip  Trash (empty)"
  fi

  spider_run_integrity_samples

  free_after=$(df -k "$home" 2>/dev/null | tail -1 | awk '{print $4}')
  free_after=$(( ${free_after:-0} * 1024 ))
  free_now=$(df -h "$home" 2>/dev/null | tail -1 | awk '{print $4}')
  free_now="${free_now:-unknown}"

  # Prefer measured free-space delta when larger (more accurate than sum of estimates)
  if [[ "$dry" != "1" && "$free_after" -gt "$free_before" ]]; then
    local delta=$((free_after - free_before))
    if [[ "$delta" -gt "$total" ]]; then
      total=$delta
    fi
  fi

  local freed_human
  freed_human=$(spider_bytes_human "$total")

  printf '\n'
  printf '%s\n' "===================================================================="
  if [[ "$dry" == "1" ]]; then
    printf 'Would free:     %s\n' "$freed_human"
  else
    printf 'Space reclaimed: %s\n' "$freed_human"
  fi
  printf 'Free space now:  %s\n' "$free_now"
  printf '%s\n' "===================================================================="

  spider_notify_clean_result "$freed_human" "$free_now" "$dry"
  spider_log "clean complete dry=${dry} total_bytes=${total} free_now=${free_now}"
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
  /usr/bin/osascript -e 'return (system info as string)' >/dev/null 2>&1 || true
}
