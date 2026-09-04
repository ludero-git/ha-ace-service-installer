#!/usr/bin/env bash
set -Eeuo pipefail

OPTIONS=${ACE_OPTIONS:-/data/run/options.json}
LOCK=/data/run/control.lock
ACTION=/data/run/current-action
MSI=/tmp/ACE-Service-Installer.msi

WINEPREFIX=${WINEPREFIX:-/opt/ace/wineprefix}
ACE_DIR="$WINEPREFIX/drive_c/Program Files (x86)/ACE Service Installer"
ACE_EXE="$ACE_DIR/ACEServiceInstaller.exe"
PATCHER=/opt/ace/tools/service-installer-patcher/ServiceInstallerPatcher.exe
PATCH_MARKER="$ACE_DIR/.patched"

LOG=${ACE_LOG:-/config/ace-service-installer.log}

OPENBOX_APPLICATION=/opt/ace/openbox/application.xml
OPENBOX_DESKTOP=/opt/ace/openbox/desktop.xml
OPENBOX_DEST=${HOME:-/data/home/ace}/.config/openbox/rc.xml

log() {
  printf '%s [control] %s\n' "$(date -Is)" "$*" >>"$LOG"
}

fail() {
  log "ERROR: $*"
  exit 1
}

option() {
  jq -r \
    --arg key "$1" \
    --arg def "$2" \
    '.[$key] // $def' \
    "$OPTIONS"
}

option_bool() {
  jq -r \
    --arg key "$1" \
    --argjson def "$2" \
    'if .[$key] == null then $def else .[$key] end' \
    "$OPTIONS"
}

setup_wine() {
  # Ensure Wine uses a UTF-8 locale for correct filename handling.
  export LANG=C.UTF-8
  export LC_ALL=C.UTF-8

  if [ "$(option_bool debug_wine false)" = true ]; then
    export WINEDEBUG='+timestamp,err+all,fixme+all'
    log "Wine debug logging enabled"
  else
    export WINEDEBUG=-all
  fi

  if [ "$(dpkg --print-architecture)" = arm64 ]; then
    export HODLL=libwow64fex.dll
    export HODLL64=libarm64ecfex.dll
  fi
}

ace_running() {
  grep -aql '[A]CEServiceInstaller.exe' /proc/[0-9]*/cmdline 2>/dev/null
}

configure_openbox() {
  mkdir -p "$(dirname "$OPENBOX_DEST")"

  if [ "${SHOW_DESKTOP:-false}" = true ]; then
    cp "$OPENBOX_DESKTOP" "$OPENBOX_DEST"
  else
    cp "$OPENBOX_APPLICATION" "$OPENBOX_DEST"
  fi
}

session_watch() {
  local target_desktop=0
  local auto_maximize="${AUTO_MAXIMIZE:-true}"
  local show_desktop="${SHOW_DESKTOP:-false}"
  local main_id=""
  local current windows id desktop x y width height host title state

  wmctrl -s "$target_desktop" >/dev/null 2>&1 || true

  while sleep 1; do
    current="$(wmctrl -d 2>/dev/null | awk '$2 == "*" {print $1; exit}')"
    [ "$current" = "$target_desktop" ] ||
      wmctrl -s "$target_desktop" >/dev/null 2>&1 || true

    windows="$(wmctrl -lG 2>/dev/null || true)"

    if [ -n "$main_id" ] &&
       ! awk -v id="$main_id" '$1 == id {found=1} END {exit !found}' <<< "$windows"; then
      main_id=""
    fi

    if [ -z "$main_id" ]; then
      while read -r id desktop x y width height host title; do
        [ -n "$id" ] || continue
        [[ "$title" =~ ^ACE[[:space:]]Service[[:space:]]Installer[[:space:]][0-9] ]] || continue
        (( width > 1000 && height > 600 )) || continue

        main_id="$id"
        break
      done <<< "$windows"
    fi

    [ -n "$main_id" ] || continue

    read -r id desktop x y width height host title < <(
      awk -v id="$main_id" '$1 == id {print; exit}' <<< "$windows"
    )
    [ -n "$id" ] || continue

    # Always keep it on the target desktop.
    if [ "$desktop" != "-1" ] && [ "$desktop" != "$target_desktop" ]; then
      wmctrl -ir "$id" -t "$target_desktop" >/dev/null 2>&1 || true
    fi

    state="$(xprop -id "$id" _NET_WM_STATE 2>/dev/null || true)"

    # Restore unless showing the desktop is allowed.
    if [ "$show_desktop" = false ] &&
       [[ "$state" == *"_NET_WM_STATE_HIDDEN"* ]]; then
      wmctrl -ir "$id" -b remove,hidden >/dev/null 2>&1 || true
      wmctrl -ia "$id" >/dev/null 2>&1 || true
    fi

    # Maximize when enabled.
    if [ "$auto_maximize" = true ] &&
       { [[ "$state" != *"_NET_WM_STATE_MAXIMIZED_VERT"* ]] ||
         [[ "$state" != *"_NET_WM_STATE_MAXIMIZED_HORZ"* ]]; }; then
      wmctrl -ir "$id" -b add,maximized_vert,maximized_horz >/dev/null 2>&1 || true
      log "Maximized ACE main window"
    fi
  done
}

apply_ace_patch() {
  local win_dir

  rm -f "$PATCH_MARKER"

  win_dir="$(winepath -w "$ACE_DIR" 9>&- 2>>"$LOG")" ||
    fail "Could not resolve ACE installation path"

  log "Applying ACE patches"

  wine "$PATCHER" "$win_dir" 9>&- >>"$LOG" 2>&1 ||
    fail "ACE patcher failed"

  touch "$PATCH_MARKER"
  log "ACE patches applied"
}

ensure_ace_patched() {
  [ -f "$PATCH_MARKER" ] || apply_ace_patch
}

download_installer() {
  local url

  url="$(option installer_download_link '')"
  [ -n "$url" ] || fail "installer_download_link is empty"

  log "Downloading ACE Service Installer"
  rm -f "$MSI"

  curl \
    -fL \
    --silent \
    --show-error \
    --retry 3 \
    --retry-all-errors \
    --connect-timeout 20 \
    "$url" \
    -o "$MSI" \
    >>"$LOG" 2>&1 ||
    fail "Could not download ACE Service Installer"
}

install_ace() {
  local rc silent win_msi

  printf '%s\n' install >"$ACTION"

  download_installer
  rm -f "$PATCH_MARKER"

  win_msi="$(winepath -w "$MSI" 9>&- 2>>"$LOG")" ||
    fail "Could not resolve installer path"

  silent="$(option_bool silent_install true)"

  if [ "$silent" = true ]; then
    log "Starting unattended MSI installation"

    set +e
    wine msiexec /i "$win_msi" /qn /norestart 9>&- >>"$LOG" 2>&1
    rc=$?
    set -e
  else
    log "Starting interactive MSI installation"

    set +e
    wine msiexec /i "$win_msi" 9>&- >>"$LOG" 2>&1
    rc=$?
    set -e
  fi

  log "msiexec returned with status $rc"

  case "$rc" in
    0|194)
      ;;
    *)
      fail "MSI installer exited with status $rc"
      ;;
  esac

  rm -f "$MSI"

  log "Checking installation path: $ACE_EXE"

  if [ ! -f "$ACE_EXE" ]; then
    log "ACE executable not found after MSI installation"
    find "$WINEPREFIX/drive_c" \
      -iname 'ACEServiceInstaller.exe' \
      -print \
      >>"$LOG" 2>&1 || true

    fail "Installation completed but ACEServiceInstaller.exe is missing"
  fi

  log "ACE executable detected"

  ensure_ace_patched

  log "ACE Service Installer installed and patched"
}

launch_ace() {
  printf '%s\n' launch >"$ACTION"

  [ -f "$ACE_EXE" ] ||
    fail "ACE Service Installer is not installed"

  ensure_ace_patched

  if ace_running; then
    log "ACE Service Installer is already running"
    return
  fi

  log "Launching ACE Service Installer"

  # Wine start is used because bash causes a stack overflow.
  if ! (
    exec 9>&-
    cd "$ACE_DIR"
    wine start /unix "$ACE_EXE" >>"$LOG" 2>&1
  ); then
    fail "Wine failed to start ACE Service Installer"
  fi

  # Wait until ACE actually appears.
  for _ in {1..30}; do
    if ace_running; then
      log "ACE Service Installer launched"
      return
    fi
    sleep 0.5
  done

  fail "ACE Service Installer process did not stay running"
}

auto_flow() {
  if [ "$(option_bool auto_install true)" = true ] && [ ! -f "$ACE_EXE" ]; then
    install_ace
  fi

  if [ ! -f "$ACE_EXE" ]; then
    if [ "$(option_bool auto_launch true)" = true ]; then
      log "Auto-launch skipped because ACE is not installed"
    fi
    return
  fi

  ensure_ace_patched

  if [ "$(option_bool auto_launch true)" = true ]; then
    launch_ace
  fi
}

command=${1:-}

case "$command" in
  configure-openbox)
    configure_openbox
    exit
    ;;
  session-watch)
    session_watch
    exit
    ;;
  install|launch|auto) ;;
  *)
    echo "Usage: $0 {configure-openbox|session-watch|install|launch|auto}" >&2
    exit 64
    ;;
esac

exec 9>"$LOCK"

if ! flock -n 9; then
  log "Another ACE operation is already running"
  exit 75
fi

printf '%s\n' "$command" >"$ACTION"
trap 'rm -f "$ACTION"' EXIT

setup_wine
log "Action started: $command"

case "$command" in
  install) install_ace ;;
  launch) launch_ace ;;
  auto) auto_flow ;;
esac

log "Action completed: $command"