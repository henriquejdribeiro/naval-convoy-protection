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
TELEMETRY_DIR = os.path.join(SIM_DIR, "game", "telemetry")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
DRONE_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")

import glob
RUN_STAT_RE = re.compile(r"(convoy-[\w-]+)=([\d.]+)%/([\d.]+)([KMG])iB")   # name, cpu%, memval, unit

def _mib(v, u):
    v = float(v)
    return v * 1024.0 if u == "G" else (v / 1024.0 if u == "K" else v)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=WEBAPP_DIR, **k)

    def _send_json(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/api/run-stats":
            try:
                return self._run_stats()
            except Exception as e:  # noqa: BLE001
                return self.send_error(500, "stats read failed: %s" % e)
        if p == "/api/node-log":
            try:
                return self._node_log()
            except Exception as e:  # noqa: BLE001
                return self.send_error(500, "log read failed: %s" % e)
        return super().do_GET()

    def _node_log(self):
        from urllib.parse import urlparse, parse_qs
        name = (parse_qs(urlparse(self.path).query).get("name") or [""])[0]
        if not re.match(r"^convoy-[a-z0-9-]{1,40}$", name):
            return self.send_error(400, "bad node name")
        runs = sorted(glob.glob(os.path.join(SIM_DIR, "demo", "runs", "metrics-*", "logs", name + ".log")))
        body = b"(no captured log for this node)"
        if runs:
            with open(runs[-1], "rb") as f:
                body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _run_stats(self):
        empty = {"t": [], "dur": 0, "containers": {}, "phases": []}
        runs = sorted(glob.glob(os.path.join(SIM_DIR, "demo", "runs", "metrics-*", "stats.log")))
        if not runs:
            return self._send_json(empty)
        path = runs[-1]
        marks, pf = [], os.path.join(os.path.dirname(path), "phases.txt")
        if os.path.exists(pf):
            with open(pf, encoding="utf-8", errors="replace") as f:
                for line in f:
                    p = line.split()
                    if len(p) >= 2 and p[1].isdigit():
                        marks.append([p[0], int(p[1])])
            marks.sort(key=lambda m: m[1])
        win0 = marks[0][1] if marks else None
        win1 = marks[-1][1] if marks else None
        times, series = [], {}
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                sp = line.split(None, 1)
                if len(sp) < 2 or not sp[0].isdigit():
                    continue
                t = int(sp[0])
                if win0 is not None and (t < win0 or t > win1):
                    continue
                times.append(t)
                for m in RUN_STAT_RE.finditer(sp[1]):
                    s = series.setdefault(m.group(1), {"cpu": [], "mem": []})
                    s["cpu"].append(round(float(m.group(2)), 1))
                    s["mem"].append(round(_mib(m.group(3), m.group(4)), 1))
        if not times:
            return self._send_json(empty)
        t0, rel = times[0], [t - times[0] for t in times]
        phases = []
        for k, (name, ep) in enumerate(marks):
            if name == "end":
                continue
            t1 = marks[k + 1][1] - t0 if k + 1 < len(marks) else rel[-1]
            phases.append({"name": name, "t0": max(0, ep - t0), "t1": max(0, t1)})
        return self._send_json({
            "run": os.path.basename(os.path.dirname(path)),
            "t": rel, "dur": rel[-1], "containers": series, "phases": phases,
        })

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
