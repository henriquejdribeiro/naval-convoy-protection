import json, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GETH = "http://host.docker.internal:8545"

def fix(obj):
    # Madara's .watch() sends eth_newFilter with toBlock:"finalized",
    # which stock geth rejects ("invalid block range params"). Rewrite it
    # to "latest"; madara still enforces finality client-side via
    # l1_messages_finality_blocks (=10), so semantics are preserved.
    try:
        if obj.get("method") == "eth_newFilter":
            p = obj.get("params")
            if isinstance(p, list) and p and isinstance(p[0], dict) and p[0].get("toBlock") == "finalized":
                p[0]["toBlock"] = "latest"
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
            req = urllib.request.Request(GETH, data=body, headers={"Content-Type": "application/json"})
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