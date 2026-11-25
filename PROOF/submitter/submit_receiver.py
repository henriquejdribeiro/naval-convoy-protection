#!/usr/bin/env python3
# submit-receiver.py — ship-side proof-submission receiver.
# Runs on the relay ship (F=alpha, B=bravo). Accepts a tar bundle
# (evm_proof.json + fact_topologies.json + safe_area_verify.json) pushed by
# this swarm's leader over mTLS, then runs the convoy-submitter CLI with THIS
# ship's relay key (PRIVATE_KEY) against the LOCAL L1 node (URL). The relay
# key never leaves the ship. Submits are serialised (one at a time) so the
# relay signer's nonce stays monotonic.
import os, io, sys, time, tarfile, threading, subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT     = int(os.environ.get("RECEIVER_PORT", "9000"))
ARCHIVE  = os.environ.get("RECEIVER_ARCHIVE_DIR", "/submissions")
EXPECT   = {"evm_proof.json", "fact_topologies.json", "safe_area_verify.json"}
VERIFIER = os.environ.get("CONVOY_VERIFIER_ADDR") or os.environ.get("VERIFIER_ADDR", "")
REQUIRED = ["URL", "PRIVATE_KEY", "GPS_STATEMENT_VERIFIER_ADDR",
            "MERKLE_STATEMENT_CONTRACT_ADDR", "FRI_STATEMENT_CONTRACT_ADDR",
            "MEMORY_PAGE_FACT_REGISTRY_ADDR"]
_LOCK = threading.Lock()          # one signer → one in-flight submit

def _safe_extract(blob, dest):
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as tf:
        for m in tf.getmembers():
            name = os.path.basename(m.name)        # strip any path (no traversal)
            if name in EXPECT and m.isfile():
                m.name = name
                tf.extract(m, dest)
    return EXPECT - set(os.listdir(dest))

class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def _reply(self, code, body):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(b))); self.end_headers()
        self.wfile.write(b)
    def do_POST(self):
        if self.path.split("?")[0] != "/submit":
            return self._reply(404, "not found\n")
        tag   = self.headers.get("X-Convoy-Tag", "run")
        swarm = self.headers.get("X-Convoy-Swarm", os.environ.get("SWARM", "?"))
        blob  = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        work  = os.path.join(ARCHIVE, f"{swarm}-{tag}-{time.strftime('%Y%m%d-%H%M%S')}")
        os.makedirs(work, exist_ok=True)
        try:
            missing = _safe_extract(blob, work)
        except Exception as e:
            return self._reply(400, f"[receiver] bad bundle: {e}\n")
        if missing:
            return self._reply(400, f"[receiver] missing from bundle: {sorted(missing)}\n")
        env = dict(os.environ)
        env.update({
            "ANNOTATED_PROOF":       os.path.join(work, "evm_proof.json"),
            "FACT_TOPOLOGIES":       os.path.join(work, "fact_topologies.json"),
            "SAFE_AREA_VERIFY_JSON": os.path.join(work, "safe_area_verify.json"),
            "CONVOY_VERIFIER_ADDR":  VERIFIER,
        })
        print(f"[receiver] {swarm}/{tag}: convoy-submitter → {env['URL']}", flush=True)
        with _LOCK:                                   # serialise: protect nonce
            p = subprocess.run(["convoy-submitter"], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = p.stdout.decode(errors="replace")
        open(os.path.join(work, "submit_log.txt"), "w").write(log)
        ok = p.returncode == 0 and "[submitter] DONE." in log
        self._reply(200 if ok else 500, log)          # echo the log back to the prover
    def log_message(self, *a):  # quiet
        pass

def main():
    miss = [v for v in REQUIRED if not os.environ.get(v)]
    if miss:  print(f"[receiver] FATAL missing env: {miss}", file=sys.stderr); sys.exit(2)
    if not VERIFIER:  print("[receiver] FATAL need CONVOY_VERIFIER_ADDR or VERIFIER_ADDR", file=sys.stderr); sys.exit(2)
    os.makedirs(ARCHIVE, exist_ok=True)
    print(f"[receiver] ship-side submitter on :{PORT} → {os.environ['URL']}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()

if __name__ == "__main__":
    main()