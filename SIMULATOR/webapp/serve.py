#!/usr/bin/env python3
"""serve.py — static server for the SIMULATOR webapp + drone telemetry writer.

Drop-in replacement for `python3 -m http.server` (pure stdlib, no deps):

    python3 serve.py [port]          # default 8000

Serves this directory (SIMULATOR/webapp) AND accepts telemetry the 3D sim
posts as you fly a drone:

    POST /api/telemetry/<drone>      body = telemetry JSON
        -> writes SIMULATOR/telemetry/<drone>/<drone>_telemetry.json

Bound to 127.0.0.1 only (it writes to disk, so it must not be reachable off
this machine). <drone> is restricted to [A-Za-z0-9_-] so it can never escape
the telemetry directory.
"""
import http.server
import socketserver
import json
import os
import re
import sys

WEBAPP_DIR = os.path.dirname(os.path.abspath(__file__))      # SIMULATOR/webapp
SIM_DIR = os.path.dirname(WEBAPP_DIR)                         # SIMULATOR
TELEMETRY_DIR = os.path.join(SIM_DIR, "telemetry")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
DRONE_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEBAPP_DIR, **k)

    def do_POST(self):
        m = re.match(r"^/api/telemetry/([^/?#]+)$", self.path)
        if not m:
            self.send_error(404, "unknown endpoint")
            return
        drone = m.group(1)
        if not DRONE_RE.match(drone):
            self.send_error(400, "bad drone id")
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(length) or b"{}")
        except Exception as e:  # noqa: BLE001
            self.send_error(400, "invalid json: %s" % e)
            return

        out_dir = os.path.join(TELEMETRY_DIR, drone)
        os.makedirs(out_dir, exist_ok=True)
        out_path = os.path.join(out_dir, "%s_telemetry.json" % drone)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
            f.write("\n")

        rel = os.path.relpath(out_path, SIM_DIR).replace("\\", "/")
        body = json.dumps({"ok": True, "path": rel, "count": len(data.get("samples", []))}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        print("SIMULATOR webapp  -> http://localhost:%d   (serving %s)" % (PORT, WEBAPP_DIR))
        print("telemetry writes  -> %s%s<drone>%s<drone>_telemetry.json" % (TELEMETRY_DIR, os.sep, os.sep))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nbye")
