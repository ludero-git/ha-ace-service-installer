#!/usr/bin/env python3

import fcntl
import json
import logging
import os
import pathlib
import subprocess
from datetime import datetime

from flask import Flask, jsonify, request
from werkzeug.utils import secure_filename

app = Flask(__name__)
logging.getLogger("werkzeug").disabled = True

RUN = pathlib.Path("/data/run")
WINEPREFIX = pathlib.Path(os.environ.get("WINEPREFIX", "/opt/ace/wineprefix"))
ACE_DIR = WINEPREFIX / "drive_c" / "Program Files (x86)" / "ACE Service Installer"
ACE_EXE = ACE_DIR / "ACEServiceInstaller.exe"
PATCH_MARKER = ACE_DIR / ".patched"
UPLOAD_DIR = WINEPREFIX / "drive_c" / "ace-files"
ACTION = RUN / "current-action"
LOCK = RUN / "control.lock"
LOG = pathlib.Path(os.environ.get("ACE_LOG", "/config/ace-service-installer.log"))
CONTROL = "/usr/local/bin/ace-control.sh"

def output(*args):
    return subprocess.check_output(
        args,
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()

BUILD = json.loads(
    pathlib.Path("/opt/ace/build-info.json").read_text(encoding="utf-8")
)

RUNTIME = {
    "arch": output("dpkg", "--print-architecture"),
    "wine_version": output("wine", "--version").removeprefix("wine-"),
    "build_version": BUILD["version"],
    "build_arch": BUILD["arch"],
    "source_hash": BUILD["source_hash"],
}

def log_message(message):
    timestamp = datetime.now().astimezone().isoformat(timespec="seconds")
    with LOG.open("a", encoding="utf-8") as log:
        log.write(f"{timestamp} [api] {message}\n")

def running():
    for cmdline in pathlib.Path("/proc").glob("[0-9]*/cmdline"):
        try:
            if b"ACEServiceInstaller.exe" in cmdline.read_bytes():
                return True
        except OSError:
            pass
    return False

def operation_active():
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o644)

    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True

        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    finally:
        os.close(fd)

def current_action():
    if not operation_active():
        try:
            ACTION.unlink()
        except FileNotFoundError:
            pass
        return None

    try:
        return ACTION.read_text(encoding="utf-8").strip() or None
    except OSError:
        return None

@app.after_request
def no_cache(response):
    response.headers["Cache-Control"] = "no-store"
    return response

@app.get("/api/health")
def health():
    return jsonify(ok=True)

@app.get("/api/status")
def status():
    action = current_action()
    is_running = running()

    if action:
        state = "working"
        label = {
            "install": "Installing...",
            "launch": "Launching...",
            "auto": "Preparing...",
        }.get(action, "Working...")
    elif is_running:
        state = "running"
        label = "Running"
    else:
        state = "ready"
        label = "Ready"

    return jsonify(
        runtime=RUNTIME,
        state=state,
        status=label,
        ready=True,
        installed=ACE_EXE.exists(),
        patched=PATCH_MARKER.exists(),
        running=is_running,
        busy=operation_active(),
        action=action,
        log_path=str(LOG),
    )

@app.get("/api/logs")
def logs():
    try:
        lines = int(request.args.get("lines", "180"))
    except ValueError:
        lines = 180

    lines = max(20, min(lines, 600))
    proc = subprocess.run(
        ["tail", "-n", str(lines), str(LOG)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    return jsonify(lines=proc.stdout.splitlines())

@app.delete("/api/logs")
def clear_logs():
    LOG.write_text("", encoding="utf-8")
    return jsonify(ok=True)

@app.post("/api/files")
def files():
    uploads = request.files.getlist("files")
    if not uploads:
        return jsonify(ok=False, error="No files provided"), 400

    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    saved = []

    for upload in uploads:
        name = secure_filename(upload.filename)
        if not name:
            continue

        path = UPLOAD_DIR / name
        upload.save(path)
        saved.append(name)

        windows_path = "C:/" + path.relative_to(WINEPREFIX / "drive_c").as_posix()
        log_message(f'Uploaded file "{name}" saved to "{windows_path}"')

    if not saved:
        return jsonify(ok=False, error="No valid files provided"), 400

    return jsonify(ok=True, files=saved)

@app.post("/api/action/<name>")
def action(name):
    if name not in {"install", "launch"}:
        return jsonify(ok=False, error="Unknown action"), 404

    if operation_active():
        return jsonify(ok=False, error="Another operation is already running"), 409

    try:
        ACTION.unlink()
    except FileNotFoundError:
        pass

    subprocess.Popen(
        [CONTROL, name],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
        env=os.environ.copy(),
    )

    return jsonify(ok=True, action=name), 202

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8098, threaded=True)