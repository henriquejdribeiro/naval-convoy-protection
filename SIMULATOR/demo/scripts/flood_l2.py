#!/usr/bin/env python3
# flood_l2.py — saturate a swarm's Madara L2 to measure max TPS.
import json, urllib.request, concurrent.futures as cf, time, sys

# ───────────────────────── CONFIG (this run) ─────────────────────────
RPC      = "http://localhost:19944/rpc/v0.8.1"
SENDER   = "0x02ec14f9442371b9662ba85b4358a858ab051052997a57092582c7529e2334ef"  # ALPHA_DRONE_1_ADDR
CONV     = "0x04f7df2655436af015551ba5c04853126beaef45889f5f36b3c64f65ba90709d"  # CONVOY_PROTOCOL_ADDR_ALPHA
SELECTOR = "0x8e9494f368e5328c75cdfbdc90fe15aea2eafcfce022a22a4278bb34c68b4d"     # submit_telemetry
MISSION  = 1
DRONE_ID = 1
N_CELLS  = 20
N_TXS    = 10000     # want enough to bouncer-cut a block
WORKERS  = 96
C_L2GAS  = 14889600  # measured cost of one SUCCESSFUL submit_telemetry (receipt)
# ──────────────────────────────────────────────────────────────────────

def rpc(method, params, timeout=30):
    req = urllib.request.Request(RPC,
        data=json.dumps({"jsonrpc":"2.0","id":1,"method":method,"params":params}).encode(),
        headers={"content-type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))

hx = lambda x: hex(x if isinstance(x,int) else int(x,0))

def inner_calldata():                       # full submit_telemetry signature
    vals = list(range(1, N_CELLS+1))
    cd = [MISSION, DRONE_ID]
    for _ in range(4):                      # cells_x, cells_y, cells_p_contact, cells_ts
        cd.append(N_CELLS); cd += vals
    cd += [0, 0, 0]                         # cells_nonce, commitment_h, drone_pubkey
    cd += [0, 0]                            # sig_r, sig_s
    for _ in range(3):                      # track_x, track_y, track_ts (empty)
        cd.append(0)
    return cd

def account_calldata():                     # OZ __execute__(Array<Call>)
    inner = inner_calldata()
    return [1, int(CONV,16), int(SELECTOR,16), len(inner)] + inner

CALLDATA = [hx(x) for x in account_calldata()]
# sane bounds: max_price ≥ network price, Σ(max_amount·max_price) ≪ balance(~1e18)
RB = {"l1_gas":     {"max_amount":"0x2000",    "max_price_per_unit":"0x80000000"},
      "l2_gas":     {"max_amount":"0x2000000", "max_price_per_unit":"0x100000"},
      "l1_data_gas":{"max_amount":"0x8000",    "max_price_per_unit":"0x100000"}}

def tx(nonce):
    return {"type":"INVOKE","version":"0x3","sender_address":SENDER,"calldata":CALLDATA,
            "signature":[],"nonce":hx(nonce),"resource_bounds":RB,"tip":"0x0",
            "paymaster_data":[],"account_deployment_data":[],
            "nonce_data_availability_mode":"L1","fee_data_availability_mode":"L1"}

def send(nonce):
    try:
        r = rpc("starknet_addInvokeTransaction", [tx(nonce)])
        return ("ok", r["result"]["transaction_hash"]) if "result" in r else ("err", r["error"])
    except Exception as e:
        return ("exc", str(e))

def main():
    base = int(rpc("starknet_getNonce", ["pending", SENDER])["result"], 16)
    print("base nonce:", base)
    s, info = send(base); print("first tx:", s, info)
    if s != "ok":
        print("fix config/bounds above before flooding."); sys.exit(1)

    start = rpc("starknet_blockNumber", [])["result"]
    t0 = time.time()
    with cf.ThreadPoolExecutor(max_workers=WORKERS) as ex:
        res = list(ex.map(send, range(base+1, base+N_TXS)))
    ok = 1 + sum(1 for x,_ in res if x == "ok")
    errs = [i for i in res if i[0] != "ok"][:3]
    print(f"submitted {ok}/{N_TXS} in {time.time()-t0:.1f}s ({ok/(time.time()-t0):.0f} tx/s)")
    if errs: print("sample errors:", errs)

    time.sleep(24)                          # let ~4 blocks seal
    end = rpc("starknet_blockNumber", [])["result"]
    best = (None, -1, [])
    for bn in range(start, end+1):
        txs = rpc("starknet_getBlockWithTxHashes", [{"block_number":bn}])["result"]["transactions"]
        if txs: print(f"  block {bn}: {len(txs)} txs")
        if len(txs) > best[1]: best = (bn, len(txs), txs)

    print(f"\nFULLEST block {best[0]}: {best[1]} txs")
    if best[2]:
        B = 0; succ = rev = 0
        for h in best[2]:
            r = rpc("starknet_getTransactionReceipt", [h])["result"]
            B += r.get("execution_resources", {}).get("l2_gas", 0)
            if r.get("execution_status") == "REVERTED": rev += 1
            else: succ += 1
        print(f"status in block: {succ} succeeded, {rev} reverted")
        print(f"block l2_gas budget  B ≈ {B:,}")
        print(f"cost per submit      C  = {C_L2GAS:,}")
        print(f"→ successful submit_telemetry per block = B/C ≈ {B/C_L2GAS:.0f}")
        print(f"→ MAX TPS / swarm = (B/C)/6 ≈ {B/C_L2GAS/6:.1f}   (α+β ≈ {2*B/C_L2GAS/6:.1f})")

if __name__ == "__main__":
    main()