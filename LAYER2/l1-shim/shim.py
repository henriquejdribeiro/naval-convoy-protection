import json, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BESU = "http://ship-a:8545"

def _relabel(x):
    # Besu-QBFT serves neither `finalized` nor `safe` (it ERRORS on the tag), yet
    # every QBFT block is final — so `latest` IS the finalized/safe block. Rewrite
    # those tags to `latest` wherever they appear as a block parameter, for ANY
    # method (eth_getBlockByNumber, eth_call, eth_getCode, eth_getStorageAt,
    # eth_getLogs, eth_newFilter, …). Madara probes the core and VALIDATES each
    # L1→L2 message with eth_call/eth_getCode at `finalized`; unrewritten, those
    # error and Madara reports "core not found" and skips the message as
    # invalid/cancelled — so open_mission never lands. These tag strings only ever
    # occur as block params in JSON-RPC, so a blanket rewrite of the params is safe.
    if isinstance(x, str):
        return "latest" if x in ("finalized", "safe") else x
    if isinstance(x, list):
        return [_relabel(v) for v in x]
    if isinstance(x, dict):
        return {k: _relabel(v) for k, v in x.items()}
    return x

def fix(obj):
    try:
        if isinstance(obj, dict) and isinstance(obj.get("params"), (list, dict)):
            obj["params"] = _relabel(obj["params"])
    except Exception:
        pass

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        try:
            data = json.loads(body)
            [fix(o) for o in data] if isinstance(data, list) else fix(data)
            body = json.dumps(data).encode()
        except Exception:
            pass
        try:
            req = urllib.request.Request(BESU, data=body, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                out, code = r.read(), r.status
        except urllib.error.HTTPError as e:
            out, code = e.read(), e.code
        except Exception as e:
            out, code = json.dumps({"jsonrpc":"2.0","id":None,"error":{"code":-32000,"message":str(e)}}).encode(), 502
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
    def log_message(self, *a):
        pass

ThreadingHTTPServer(("0.0.0.0", 8545), H).serve_forever()