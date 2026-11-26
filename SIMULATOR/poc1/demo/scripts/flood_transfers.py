#!/usr/bin/env python3
# flood_transfers.py — signed STRK self-transfers via the drone's own starkli,
# to saturate the L2 and read the block l2_gas budget B. Then max TPS = B/C/6.
import urllib.request, json, subprocess, time, os, sys
RPC    = "http://localhost:19944/rpc/v0.8.1"
MACH   = "convoy-machine-alpha-1"
RPC_IN = "http://convoy-madara-alpha:9944/rpc/v0.8.1"
STRK   = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
SELF   = "0x02ec14f9442371b9662ba85b4358a858ab051052997a57092582c7529e2334ef"  # drone1 (recipient = self)
N      = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
PAR    = int(sys.argv[2]) if len(sys.argv) > 2 else 24
C      = 14889600   # measured l2_gas per successful submit_telemetry

def rpc(m, p):
    req = urllib.request.Request(RPC, data=json.dumps({"jsonrpc":"2.0","id":1,"method":m,"params":p}).encode(),
                                 headers={"content-type":"application/json"})
    return json.load(urllib.request.urlopen(req))["result"]

base  = int(rpc("starknet_getNonce", ["pending", SELF]), 16)
start = rpc("starknet_blockNumber", [])
print(f"base nonce {base}, start block {start} — flooding {N} signed STRK transfers ({PAR}-parallel)...")

nonces = "\n".join(str(base+i) for i in range(N))
inner  = (f'xargs -P {PAR} -I{{}} starkli invoke {STRK} transfer {SELF} 1 0 '
              f'--rpc {RPC_IN} --nonce {{}} '
              f'--l1-gas 1000 --l1-gas-price-raw 2000000000000 '
              f'--l2-gas 10000000 --l2-gas-price-raw 2000000000 '
              f'--l1-data-gas 100000 --l1-data-gas-price-raw 2000000000 '
              f'>/dev/null 2>&1')
t0 = time.time()
subprocess.run(["docker","exec","-i",MACH,"bash","-c",inner], input=nonces, text=True,
               env={**os.environ, "MSYS_NO_PATHCONV":"1"})
print(f"flood submitted in {time.time()-t0:.0f}s")

now = int(rpc("starknet_getNonce", ["pending", SELF]), 16)
print(f"drone1 nonce now: {now}  ({'MINING ✓' if now > base else 'still stuck — signing/other issue'})")

time.sleep(18)
end  = rpc("starknet_blockNumber", [])
best = (None, -1, [])
for bn in range(start, end+1):
    txs = rpc("starknet_getBlockWithTxHashes", [{"block_number":bn}])["transactions"]
    if txs: print(f"  block {bn}: {len(txs)} txs")
    if len(txs) > best[1]: best = (bn, len(txs), txs)

print(f"\nFULLEST block {best[0]}: {best[1]} txs")
if best[2]:
    B = succ = rev = 0
    for h in best[2]:
        r = rpc("starknet_getTransactionReceipt", [h])
        B += r.get("execution_resources", {}).get("l2_gas", 0)
        rev += r.get("execution_status") == "REVERTED"; succ += r.get("execution_status") != "REVERTED"
    print(f"status: {succ} ok, {rev} reverted ; block l2_gas budget B ≈ {B:,}")
    print(f"→ submit_telemetry per block = B/C ≈ {B/C:.0f}")
    print(f"→ MAX TPS / swarm ≈ {B/C/6:.1f}   (α+β ≈ {2*B/C/6:.1f})")