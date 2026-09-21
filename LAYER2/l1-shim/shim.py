import json, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BESU = "http://ship-a:8545"

def fix(obj):
    # Besu-QBFT doesn't expose the `finalized` tag (QBFT finalizes every block,
    # so `latest` IS final). Madara touches `finalized` two ways — rewrite both:
    #   1. eth_newFilter toBlock:"finalized"    (event scan)
    #   2. eth_getBlockByNumber "finalized"      (L1→L2 finality counter)
    # Without (2) the message sync sticks at N/10 confirmations forever, because
    # Besu never advances `finalized`.
    try:
        m = obj.get("method")
        p = obj.get("params")
        if m == "eth_newFilter":
            if isinstance(p, list) and p and isinstance(p[0], dict) and p[0].get("toBlock") == "finalized":
                p[0]["toBlock"] = "latest"
        elif m == "eth_getBlockByNumber":
            if isinstance(p, list) and p and p[0] == "finalized":
                p[0] = "latest"
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