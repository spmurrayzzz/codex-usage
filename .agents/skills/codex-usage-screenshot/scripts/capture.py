#!/usr/bin/env python3
"""Capture a Codex Usage README screenshot from a live window running on mock data."""

import argparse
import base64
import json
import os
import shutil
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
import zlib
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_DIR = Path(__file__).resolve().parent
DEMO_DIR = Path("/tmp/codex-usage-demo")
MOCK_ACCOUNT = "00000000-0000-4000-8000-000000000000"
STRIP_CHUNKS = (b"eXIf", b"Exif", b"xMP", b"iTXt", b"tEXt", b"zTXt")
DEFAULT_WIDTH = 0


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def default_fixtures(now):
    usage = {
        "email": "demo@example.com",
        "account_id": MOCK_ACCOUNT,
        "plan_type": "promax",
        "rate_limit": {
            "allowed": True,
            "limit_reached": False,
            "primary_window": {
                "limit_window_seconds": 604800,
                "used_percent": 32,
                "reset_at": now + 5 * 86400 + 7 * 3600,
            },
        },
        "credits": {
            "has_credits": True,
            "unlimited": False,
            "balance": 50000,
            "approx_local_messages": [12500, 65000],
            "approx_cloud_messages": [2000, 12500],
        },
        "model_usage": {
            "gpt-6-astra": {"available": True, "credits_would_enable": False},
        },
        "rate_limit_reset_credits": {
            "applicable_available_count": 0,
            "available_count": 2,
        },
    }
    reset_credits = {
        "available_count": 2,
        "total_earned_count": 2,
        "credits": [
            {
                "id": "demo-credit-1",
                "title": "Full reset",
                "status": "available",
                "granted_at": now - 3 * 86400,
                "expires_at": now + 10 * 86400,
            },
            {
                "id": "demo-credit-2",
                "title": "Full reset",
                "status": "available",
                "granted_at": now - 6 * 86400,
                "expires_at": now + 17 * 86400,
            },
        ],
    }
    return {"usage": usage, "reset_credits": reset_credits}


class MockHandler(BaseHTTPRequestHandler):
    fixtures = None
    log = None
    lock = None

    def do_GET(self):
        if self.path == "/backend-api/wham/usage":
            body = json.dumps(self.fixtures["usage"]).encode()
        elif self.path == "/backend-api/wham/rate-limit-reset-credits":
            body = json.dumps(self.fixtures["reset_credits"]).encode()
        else:
            self.send_response(404)
            self.end_headers()
            return
        with self.lock:
            self.log.append(self.path)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def write_auth(now):
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    payload = b64url(
        json.dumps(
            {
                "exp": now + 30 * 86400,
                "chatgpt_account_id": MOCK_ACCOUNT,
            }
        ).encode()
    )
    auth = {
        "auth_mode": "chatgpt",
        "last_refresh": datetime.fromtimestamp(now, tz=timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "tokens": {
            "access_token": f"{header}.{payload}.mock-signature",
            "refresh_token": "mock-refresh-token-never-use",
            "account_id": MOCK_ACCOUNT,
        },
    }
    (DEMO_DIR / "auth.json").write_text(json.dumps(auth, indent=2, sort_keys=True) + "\n")


def kill_stale_demo():
    pid_file = DEMO_DIR / "app.pid"
    if pid_file.exists():
        try:
            pid = int(pid_file.read_text().strip())
            os.kill(pid, signal.SIGTERM)
            deadline = time.time() + 5
            while time.time() < deadline:
                try:
                    os.kill(pid, 0)
                    time.sleep(0.1)
                except ProcessLookupError:
                    break
        except (ValueError, ProcessLookupError, PermissionError, OSError):
            pass
    shutil.rmtree(DEMO_DIR, ignore_errors=True)


def port_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def find_window(pid, timeout=20):
    deadline = time.time() + timeout
    while time.time() < deadline:
        result = subprocess.run(
            ["swift", str(SCRIPT_DIR / "window_id.swift"), str(pid)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        if lines:
            return lines[0]
        time.sleep(2)
    return None


def png_size(path):
    with open(path, "rb") as f:
        data = f.read(33)
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", data[16:24])


def resize_to_width(raw, out, width):
    width_px, _ = png_size(raw)
    if width > 0 and width_px > width:
        result = subprocess.run(
            ["sips", "--resampleWidth", str(width), str(raw), "--out", str(out)]
        )
        if result.returncode != 0:
            fail(f"sips resize failed (exit {result.returncode})")
        return True
    shutil.copyfile(raw, out)
    return False


def strip_chunks(path):
    data = path.read_bytes()
    out = bytearray(data[:8])
    i = 8
    removed, kept = [], []
    while i < len(data):
        (length,) = struct.unpack(">I", data[i : i + 4])
        ctype = data[i + 4 : i + 8]
        payload = data[i + 4 : i + 8 + length]
        (crc,) = struct.unpack(">I", data[i + 8 + length : i + 12 + length])
        if crc != (zlib.crc32(payload) & 0xFFFFFFFF):
            fail(f"corrupt PNG chunk {ctype!r} in {path}")
        end = i + 12 + length
        if ctype in STRIP_CHUNKS:
            removed.append(ctype.decode())
        else:
            kept.append(ctype.decode())
            out += data[i:end]
        i = end
    path.write_bytes(bytes(out))
    return removed, kept


def main():
    parser = argparse.ArgumentParser(
        description="Capture a Codex Usage README screenshot with mock data."
    )
    parser.add_argument("--app", default=str(REPO_ROOT / "CodexUsage.app"))
    parser.add_argument("--out", default=str(REPO_ROOT / "assets" / "readme" / "codex-usage.png"))
    parser.add_argument("--fixtures", help="JSON file with usage and reset_credits keys")
    parser.add_argument("--port", type=int, default=8931)
    parser.add_argument(
        "--width",
        type=int,
        default=DEFAULT_WIDTH,
        help="target output width in pixels (0 keeps the raw capture size)",
    )
    parser.add_argument("--keep", action="store_true", help="keep the demo dir and app running")
    args = parser.parse_args()

    binary = Path(args.app) / "Contents" / "MacOS" / "CodexUsage"
    if not binary.exists():
        fail(f"{binary} not found. Run `make app` first.")

    kill_stale_demo()
    if not port_free(args.port):
        fail(f"port {args.port} is in use; pick another with --port")

    now = int(time.time())
    DEMO_DIR.mkdir(parents=True)
    if args.fixtures:
        fixtures = json.loads(Path(args.fixtures).read_text())
    else:
        fixtures = default_fixtures(now)
    (DEMO_DIR / "fixtures.json").write_text(json.dumps(fixtures, indent=2))
    (DEMO_DIR / "config.toml").write_text(
        f'chatgpt_base_url = "http://127.0.0.1:{args.port}/backend-api"\n'
    )
    write_auth(now)

    MockHandler.fixtures = fixtures
    MockHandler.log = []
    MockHandler.lock = threading.Lock()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), MockHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    env = dict(os.environ)
    env["CODEX_HOME"] = str(DEMO_DIR)
    app_log = open(DEMO_DIR / "app.log", "wb")
    proc = subprocess.Popen([str(binary)], env=env, stdout=app_log, stderr=subprocess.STDOUT)
    (DEMO_DIR / "app.pid").write_text(str(proc.pid))
    print(f"demo app pid: {proc.pid}, mock port: {args.port}")

    try:
        deadline = time.time() + 30
        needed = {"/backend-api/wham/usage", "/backend-api/wham/rate-limit-reset-credits"}
        while time.time() < deadline:
            with MockHandler.lock:
                seen = set(MockHandler.log)
            if needed <= seen:
                break
            if proc.poll() is not None:
                fail(f"demo app exited early with code {proc.returncode}; see {DEMO_DIR / 'app.log'}")
            time.sleep(0.25)
        else:
            fail(
                "mock server did not receive usage and reset-credits requests within 30s; "
                f"see {DEMO_DIR / 'app.log'}"
            )

        window_id = find_window(proc.pid)
        if not window_id:
            fail(f"no on-screen window found for pid {proc.pid} within 20s")

        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        raw = DEMO_DIR / "capture-raw.png"
        result = subprocess.run(["screencapture", "-x", "-l", str(window_id), str(raw)])
        if result.returncode != 0 or not raw.exists():
            fail(
                f"screencapture failed (exit {result.returncode}); "
                "does the terminal have Screen Recording permission?"
            )
        resized = resize_to_width(raw, out, args.width)
        removed, kept = strip_chunks(out)
        width_px, height_px = png_size(out)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
        app_log.close()
        server.shutdown()
        if not args.keep:
            shutil.rmtree(DEMO_DIR, ignore_errors=True)

    print(f"window: {window_id}, resized to {args.width}px: {resized}")
    print(f"wrote {out} ({width_px}x{height_px}), removed chunks: {removed or 'none'}, kept: {kept}")
    if args.keep:
        print(f"kept {DEMO_DIR} and app pid {proc.pid} for inspection")


if __name__ == "__main__":
    main()
