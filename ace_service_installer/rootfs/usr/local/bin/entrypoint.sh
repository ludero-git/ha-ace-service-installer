#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_OPTIONS=/data/options.json
RUNTIME_OPTIONS=/data/run/options.json
LOG=${ACE_LOG:-/config/ace-service-installer.log}
WINEPREFIX=${WINEPREFIX:-/opt/ace/wineprefix}

install -d -o ace -g ace -m 0755 \
  /data/home/ace \
  /data/home/ace/Desktop \
  /data/home/ace/Documents \
  /data/home/ace/Downloads \
  /data/run

install -d -o ace -g ace -m 0700 /tmp/runtime-ace
mkdir -p /config

install -o ace -g ace -m 0600 "$SOURCE_OPTIONS" "$RUNTIME_OPTIONS"
export ACE_OPTIONS="$RUNTIME_OPTIONS"

rm -f /data/run/current-action

touch "$LOG"
chown ace:ace "$LOG"
chmod 0644 "$LOG"

# Clear the logs.
: > "$LOG"

log() {
  printf '%s [entrypoint] %s\n' "$(date -Is)" "$*" | tee -a "$LOG"
}

option_bool() {
  jq -r \
    --arg key "$1" \
    --argjson def "$2" \
    'if .[$key] == null then $def else .[$key] end' \
    "$RUNTIME_OPTIONS"
}

terminate() {
  trap - TERM INT EXIT

  log "Stopping ACE environment"

  kill \
    "${SESSION_PID:-}" \
    "${AUTO_PID:-}" \
    "${API_PID:-}" \
    "${WS_PID:-}" \
    "${VNC_PID:-}" \
    "${TINT_PID:-}" \
    "${OPENBOX_PID:-}" \
    "${XVFB_PID:-}" \
    "${NGINX_PID:-}" \
    2>/dev/null || true

  wait 2>/dev/null || true
}

trap terminate TERM INT EXIT

log "Starting X11 display"

runuser -u ace -- env \
  DISPLAY=:0 \
  XDG_RUNTIME_DIR=/tmp/runtime-ace \
  Xvfb :0 -screen 0 1280x800x24 -nolisten tcp -ac \
  >>"$LOG" 2>&1 &
XVFB_PID=$!

for _ in {1..50}; do
  if runuser -u ace -- env DISPLAY=:0 xdpyinfo >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

runuser -u ace -- env DISPLAY=:0 xdpyinfo >/dev/null 2>&1 || {
  log "ERROR: Xvfb did not become ready"
  exit 1
}

SHOW_DESKTOP="$(option_bool show_desktop false)"
AUTO_MAXIMIZE="$(option_bool auto_maximize true)"

log "Configuring Openbox"

runuser -u ace -- env \
  HOME=/data/home/ace \
  SHOW_DESKTOP="$SHOW_DESKTOP" \
  /usr/local/bin/ace-control.sh configure-openbox \
  >>"$LOG" 2>&1

log "Starting Openbox"

runuser -u ace -- env \
  DISPLAY=:0 \
  HOME=/data/home/ace \
  XDG_RUNTIME_DIR=/tmp/runtime-ace \
  openbox \
  >>"$LOG" 2>&1 &
OPENBOX_PID=$!

log "Starting X11 session controller"

runuser -u ace -- env \
  DISPLAY=:0 \
  HOME=/data/home/ace \
  SHOW_DESKTOP="$SHOW_DESKTOP" \
  AUTO_MAXIMIZE="$AUTO_MAXIMIZE" \
  /usr/local/bin/ace-control.sh session-watch \
  >>"$LOG" 2>&1 &
SESSION_PID=$!

if [ "$SHOW_DESKTOP" = true ]; then
  log "Desktop mode enabled"

  runuser -u ace -- env \
    DISPLAY=:0 \
    HOME=/data/home/ace \
    tint2 \
    >>"$LOG" 2>&1 &
  TINT_PID=$!
else
  log "Application mode enabled"
fi

log "Starting VNC transport"

runuser -u ace -- env \
  DISPLAY=:0 \
  x11vnc \
    -display :0 \
    -forever \
    -shared \
    -localhost \
    -rfbport 5900 \
    -nopw \
    -noxdamage \
  >>"$LOG" 2>&1 &
VNC_PID=$!

runuser -u ace -- \
  websockify 6080 127.0.0.1:5900 \
  >>"$LOG" 2>&1 &
WS_PID=$!

log "Starting control API"

runuser -u ace -- env \
  DISPLAY=:0 \
  HOME=/data/home/ace \
  WINEPREFIX="$WINEPREFIX" \
  WINEARCH=win64 \
  XDG_RUNTIME_DIR=/tmp/runtime-ace \
  ACE_LOG="$LOG" \
  ACE_OPTIONS="$RUNTIME_OPTIONS" \
  python3 /usr/local/bin/ace-api.py \
  >>"$LOG" 2>&1 &
API_PID=$!

log "Starting nginx ingress server"

nginx -g 'daemon off;' >>"$LOG" 2>&1 &
NGINX_PID=$!

log "Starting automatic ACE actions"

runuser -u ace -- env \
  DISPLAY=:0 \
  HOME=/data/home/ace \
  WINEPREFIX="$WINEPREFIX" \
  WINEARCH=win64 \
  XDG_RUNTIME_DIR=/tmp/runtime-ace \
  ACE_LOG="$LOG" \
  ACE_OPTIONS="$RUNTIME_OPTIONS" \
  /usr/local/bin/ace-control.sh auto \
  >/dev/null 2>&1 &
AUTO_PID=$!

CORE_PIDS=(
  "$XVFB_PID"
  "$OPENBOX_PID"
  "$SESSION_PID"
  "$VNC_PID"
  "$WS_PID"
  "$API_PID"
  "$NGINX_PID"
)

WATCH_PIDS=(
  "${CORE_PIDS[@]}"
  "$AUTO_PID"
)

while true; do
  EXITED_PID=""

  if wait -n -p EXITED_PID "${WATCH_PIDS[@]}"; then
    rc=0
  else
    rc=$?
  fi

  if [ -z "${EXITED_PID:-}" ]; then
    log "ERROR: wait -n returned code $rc without identifying an exited process"
    log "WATCH_PIDS: ${WATCH_PIDS[*]}"
    exit "$rc"
  fi

  if [ "$EXITED_PID" = "$AUTO_PID" ]; then
    if [ "$rc" -ne 0 ]; then
      log "ERROR: Automatic ACE actions failed with code $rc"
      exit "$rc"
    fi

    log "Automatic ACE actions completed"

    WATCH_PIDS=("${CORE_PIDS[@]}")
    continue
  fi

  log "A core service (PID $EXITED_PID) exited with code $rc"
  exit "$rc"
done