# E2E Pipeline Run — Clean Rebuild — 2026-07-09

**Result:** full L1→L2→L1 loop + convoy advance, from a clean-from-scratch rebuild.
`isDualSafe(1,2) = true`, `ConvoyAdvance` emitted, `advanceCount = 1`.
Validates the Option-A Registry fix (no "not all drones SAFE" revert).

## Addresses
- L1 (deterministic): Registry `0xe7f1…`, Verifier `0x9fE4…`, Stub `0x5FbD…`, CommandLog `0xCf7E…`
- L2 convoy (this rebuild): alpha `0x05f46c…`, bravo `0x05e726c8…`

## Steps & output

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/up.sh
═══════════════════════════════════════════════════════════════
  [1/4] L1 chain — 6 geth ships + wire-mesh
═══════════════════════════════════════════════════════════════
 Container convoy-ship-b Started 
 Container convoy-wire-mesh Starting 
 Container convoy-wire-mesh Started 
  waiting for ship-a healthy... ✓

═══════════════════════════════════════════════════════════════
  [2/4] L1 contracts — Stub, Registry, Verifier, CommandLog
═══════════════════════════════════════════════════════════════
[deploy-l1] installing forge dependencies
[deploy-l1] building
[deploy-l1] deploying convoy contracts (Stage A/B refactor)
  StarknetCoreStub deployed at: 0x5FbDB2315678afecb367f032d93F642f64180aa3
  Registry         deployed at: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  Verifier         deployed at: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
  CommandLog       deployed at: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
[deploy-l1] L1 contracts deployed; run ./scripts/register-missions.sh after L2 setup to register missions

═══════════════════════════════════════════════════════════════
  [3/4] L2 stack — 10 Madara + 2 pathfinder leaders + prover APIs
═══════════════════════════════════════════════════════════════
 Container convoy-madara-bravo-3 Started 
 Container convoy-madara-bravo-4 Started 
 Container convoy-madara-bravo-5 Started 
  waiting for madara-alpha (sequencer) healthy... ✓
  waiting for madara-bravo (sequencer) healthy... ✓
  waiting for pathfinder-alpha-1 (leader archive) healthy..... ✓
  waiting for pathfinder-bravo-1 (leader archive) healthy... ✓

═══════════════════════════════════════════════════════════════
  [4/4] Dozzle log viewer
═══════════════════════════════════════════════════════════════
 Container convoy-debugger Created 
 Container convoy-debugger Starting 
 Container convoy-debugger Started 
  → http://localhost:8888  (sidebar grouped by drone hardware)

═══════════════════════════════════════════════════════════════
  Stack is up. Suggested next steps:
═══════════════════════════════════════════════════════════════
    ./scripts/deploy-l2.sh
    ./scripts/generate-drone-accounts.sh --swarm both
    ./scripts/register-missions.sh
    ./scripts/open-missions.sh
    python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/
    for swarm in alpha bravo; do
        for did in 1 2 3 4 5; do
            f=.tmp-l2/missions/both-safe/${swarm}_${did}.json
            [ -f "$f" ] && ./scripts/submit-telemetry.sh $swarm $did "$f"
        done
    done

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/deploy-l2.sh
WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
[deploy-l2] account: 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d

======================================================================
  Deploying convoy_protocol to convoy-madara-alpha  (swarm=alpha)
  RPC: http://convoy-madara-alpha:9944/rpc/v0.8.1
======================================================================
[deploy-l2/alpha] computing class hash...
[deploy-l2/alpha] class_hash: 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/alpha] declaring convoy_protocol...
Transaction 0x01fa0a59553c6adb17a5adef36e7632d7f5c1577e6278a756796280298a4c914 confirmed
Class hash declared:
0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/alpha] deploying contract...
  constructor: l1_commander=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, l1_verifier=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/deploy-l2.sh
WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
[deploy-l2] account: 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d

======================================================================
  Deploying convoy_protocol to convoy-madara-alpha  (swarm=alpha)
  RPC: http://convoy-madara-alpha:9944/rpc/v0.8.1
======================================================================
[deploy-l2/alpha] computing class hash...
[deploy-l2/alpha] class_hash: 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/alpha] declaring convoy_protocol...
WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Not declaring class as it's already declared. Class hash:
0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/alpha] deploying contract...
  constructor: l1_commander=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, l1_verifier=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Waiting for transaction 0x053def9ffc8777a8473b8ff9eb4b3000cd66e0cf94ef5d869072995b9bb249a0 to confirm...
Transaction not confirmed yet...
Transaction 0x053def9ffc8777a8473b8ff9eb4b3000cd66e0cf94ef5d869072995b9bb249a0 confirmed
Contract deployed:
0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
[deploy-l2/alpha] contract_addr: 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
[deploy-l2/alpha] wrote .tmp-l2/convoy_l2_alpha.env
[deploy-l2/alpha] smoke test: safe_count(0) (expect 0x0)...

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/deploy-l2.sh --swarm bravo
WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
[deploy-l2] account: 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d

======================================================================
  Deploying convoy_protocol to convoy-madara-bravo  (swarm=bravo)
  RPC: http://convoy-madara-bravo:9944/rpc/v0.8.1
======================================================================
[deploy-l2/bravo] computing class hash...
[deploy-l2/bravo] class_hash: 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/bravo] declaring convoy_protocol...
Transaction 0x01337aa0846dee76015b6e2d37525fe883b157c34b14f62aa910766c57588ada confirmed
Class hash declared:
0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/bravo] deploying contract...
  constructor: l1_commander=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, l1_verifier=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Deploying class 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017 with salt 0x04e5c0ed9a17d6d3642aac541f856d1b8b4eae60c8328d18dcdf8f69f5e7941c...
The contract will be deployed at address 0x0681baa9d0b55ccae1c14be58d450d2d5788b3cc74c633b7f85b448dd230d51c
Error: TransactionExecutionError (tx index 0): Message(
    "Transaction execution has failed:\n0: Error in the called contract (contract address: 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d, class hash: 0x00e2eb8f5672af4e6a4e8a8f1b44989685e668489b0a25437733756c5a34a1d6, selector: 0x015d40a3d6ca2ac30f4031e42be28da9b056fef9bb7357ac5e85627ee876e5ad):\n1: Error in the called contract (contract address: 0x041a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf, class hash: 0x07b3e05f48f0c69e4a65ce5e076a66271a527aff2c34ce1083ec6e1526997a69, selector: 0x01987cbd17808b9a23693d4de7e246a443cfe37e6e7fbaeabd7d7e6532b07c3d):\n2: Error in the contract class constructor (contract address: 0x0681baa9d0b55ccae1c14be58d450d2d5788b3cc74c633b7f85b448dd230d51c, class hash: 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017, selector: UNKNOWN):\nClass with hash 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017 is not declared.\n",
)
[deploy-l2/bravo] contract_addr: 0x0681baa9d0b55ccae1c14be58d450d2d5788b3cc74c633b7f85b448dd230d51c
[deploy-l2/bravo] wrote .tmp-l2/convoy_l2_bravo.env
[deploy-l2/bravo] smoke test: safe_count(0) (expect 0x0)...
[deploy-l2/bravo] smoke OK

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/deploy-l2.sh --swarm bravo
WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
[deploy-l2] account: 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d

======================================================================
  Deploying convoy_protocol to convoy-madara-bravo  (swarm=bravo)
  RPC: http://convoy-madara-bravo:9944/rpc/v0.8.1
======================================================================
[deploy-l2/bravo] computing class hash...
[deploy-l2/bravo] class_hash: 0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
[deploy-l2/bravo] declaring convoy_protocol...
WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
0x01b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017
Not declaring class as it's already declared. Class hash:
[deploy-l2/bravo] deploying contract...
  constructor: l1_commander=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512, l1_verifier=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
Waiting for transaction 0x00b895614eee40c2c91136c3d8b2cc5c74e356a5929e71e866ff162527d1e78c to confirm...
Transaction not confirmed yet...
Transaction 0x00b895614eee40c2c91136c3d8b2cc5c74e356a5929e71e866ff162527d1e78c confirmed
Contract deployed:
0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
[deploy-l2/bravo] contract_addr: 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
[deploy-l2/bravo] wrote .tmp-l2/convoy_l2_bravo.env
[deploy-l2/bravo] smoke test: safe_count(0) (expect 0x0)...
[deploy-l2/bravo] smoke OK

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ source .tmp-l2/convoy_l2_alpha.env; source .tmp-l2/convoy_l2_bravo.env

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ curl -s -X POST http://localhost:19944/rpc/v0.8.1 -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"starknet_getClassHashAt\",\"params\":[\"latest\",\"${CONVOY_PROTOCOL_ADDR_ALPHA}\"],\"id\":1}"; echo
{"jsonrpc":"2.0","result":"0x1b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017","id":1}

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ curl -s -X POST http://localhost:29944/rpc/v0.8.1 -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"starknet_getClassHashAt\",\"params\":[\"latest\",\"${CONVOY_PROTOCOL_ADDR_BRAVO}\"],\"id\":1}"; echo
{"jsonrpc":"2.0","result":"0x1b7dcda7fc2aa53918329035122629761934699c101631934df9694644d9017","id":1}

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/generate-drone-accounts.sh --swarm both

======================================================================
  Minting 5 drone accounts on convoy-madara-alpha
  (deployer: account #1 at 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d)
======================================================================
[mint/alpha/1] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x0255362e1f13153640f42792dd4f6116db496f3275e29c60acfb48eb1ac0be23
[mint/alpha/2] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x01780ad5224e90988a47fb3ced917d6b1619e25ab360f79988353d28aa1e324f
[mint/alpha/3] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x049cde5c76b9e36d72ac86ad3c2f835211e554f84fbc39e1f76117f32d4e4737
[mint/alpha/4] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x00818f630c2acc57591920e954e8000e8825b9e3286a6b5bc9623168710113ef
[mint/alpha/5] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x0243f3cb04a683990b3c59033a46031d0d4c00083cd688bd3b19f81fe15edce2

[mint/alpha] wrote .tmp-l2/drones-alpha.env
# Generated by generate-drone-accounts.sh — do not commit
# Swarm: alpha    Madara: convoy-madara-alpha

ALPHA_DRONE_1_ADDR=0x0255362e1f13153640f42792dd4f6116db496f3275e29c60acfb48eb1ac0be23
ALPHA_DRONE_1_PUBKEY=0x01dbe7480770880793d9d2374bc36c0d265750e10bde36e8d735f3182a9d7b5f
ALPHA_DRONE_1_KEYSTORE=.tmp-l2/drones/alpha/1/keystore.json

ALPHA_DRONE_2_ADDR=0x01780ad5224e90988a47fb3ced917d6b1619e25ab360f79988353d28aa1e324f
ALPHA_DRONE_2_PUBKEY=0x01a7dec488741dd26f687ddd4096a01768b35174f3ee6a6769b50c8e7deb85fe
ALPHA_DRONE_2_KEYSTORE=.tmp-l2/drones/alpha/2/keystore.json

ALPHA_DRONE_3_ADDR=0x049cde5c76b9e36d72ac86ad3c2f835211e554f84fbc39e1f76117f32d4e4737
ALPHA_DRONE_3_PUBKEY=0x05a674ac29488ad1b99bacc33ad2fa9e30df78a80511b05090a670ab0ec09ba4
ALPHA_DRONE_3_KEYSTORE=.tmp-l2/drones/alpha/3/keystore.json

ALPHA_DRONE_4_ADDR=0x00818f630c2acc57591920e954e8000e8825b9e3286a6b5bc9623168710113ef
ALPHA_DRONE_4_PUBKEY=0x03fd3d9ec18c35aca349a4ab29dbdfefef8bb45b05f5f1ab2a77f8d4b5941fb2
ALPHA_DRONE_4_KEYSTORE=.tmp-l2/drones/alpha/4/keystore.json

ALPHA_DRONE_5_ADDR=0x0243f3cb04a683990b3c59033a46031d0d4c00083cd688bd3b19f81fe15edce2
ALPHA_DRONE_5_PUBKEY=0x043214768cbef4e05d3bdfc68c2856427762041336eeef3d5141d5076e33a049
ALPHA_DRONE_5_KEYSTORE=.tmp-l2/drones/alpha/5/keystore.json


[fund/alpha] funding 5 drones with 1000000000000000000 wei STRK + ETH each...
  [1/5] 0x0255362e1f13153640f42792dd4f6116db496f3275e29c60acfb48eb1ac0be23... OK
  [2/5] 0x01780ad5224e90988a47fb3ced917d6b1619e25ab360f79988353d28aa1e324f... OK
  [3/5] 0x049cde5c76b9e36d72ac86ad3c2f835211e554f84fbc39e1f76117f32d4e4737... OK
  [4/5] 0x00818f630c2acc57591920e954e8000e8825b9e3286a6b5bc9623168710113ef... OK
  [5/5] 0x0243f3cb04a683990b3c59033a46031d0d4c00083cd688bd3b19f81fe15edce2... OK

======================================================================
  Minting 5 drone accounts on convoy-madara-bravo
  (deployer: account #1 at 0x055be462e718c4166d656d11f89e341115b8bc82389c3762a10eade04fcb225d)
======================================================================
[mint/bravo/1] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x06d4bfc6c29f574936c768c3c44e5e7e7d7eea4c486ae056132f734ad736d64d
[mint/bravo/2] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x001baabf368b1244e017d625d2269f9842c3168955c7ecacfa4b777241b3db86
[mint/bravo/3] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x00d0b89bcb4d9be82c90dd2aceeadf852811753c9be47017007d950c876b7e63
[mint/bravo/4] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x073fa2e755625f82d488cc844978b90f436960665c03176340dc08428a98595c
[mint/bravo/5] deploying drone account...WARNING: setting passwords via --password is generally considered insecure, as they will be stored in your shell history or other log files.
 OK  addr=0x016140ddc4195222fba28e8cae0b864d6052c2621dea0d228c02002f84850a41

[mint/bravo] wrote .tmp-l2/drones-bravo.env
# Generated by generate-drone-accounts.sh — do not commit
# Swarm: bravo    Madara: convoy-madara-bravo

BRAVO_DRONE_1_ADDR=0x06d4bfc6c29f574936c768c3c44e5e7e7d7eea4c486ae056132f734ad736d64d
BRAVO_DRONE_1_PUBKEY=0x016ddb5c5dc746dda560a16478fd1793da194966f6a3375d4d86d38e00590cbb
BRAVO_DRONE_1_KEYSTORE=.tmp-l2/drones/bravo/1/keystore.json

BRAVO_DRONE_2_ADDR=0x001baabf368b1244e017d625d2269f9842c3168955c7ecacfa4b777241b3db86
BRAVO_DRONE_2_PUBKEY=0x01a9f448feb2d1f6c48d746c17d5335856eeb28526479541d1f217dd9def7412
BRAVO_DRONE_2_KEYSTORE=.tmp-l2/drones/bravo/2/keystore.json

BRAVO_DRONE_3_ADDR=0x00d0b89bcb4d9be82c90dd2aceeadf852811753c9be47017007d950c876b7e63
BRAVO_DRONE_3_PUBKEY=0x01e4b62f8aef48c91745a22cdb3f29c3ed4e62ebf7ab0406e3e65d05b0051a63
BRAVO_DRONE_3_KEYSTORE=.tmp-l2/drones/bravo/3/keystore.json

BRAVO_DRONE_4_ADDR=0x073fa2e755625f82d488cc844978b90f436960665c03176340dc08428a98595c
BRAVO_DRONE_4_PUBKEY=0x06ef03438186e76cd49072489a40f68e62679e627c19928f828cbf7afc959690
BRAVO_DRONE_4_KEYSTORE=.tmp-l2/drones/bravo/4/keystore.json

BRAVO_DRONE_5_ADDR=0x016140ddc4195222fba28e8cae0b864d6052c2621dea0d228c02002f84850a41
BRAVO_DRONE_5_PUBKEY=0x03f789772eb4a90b631059f70143562b1b3637ce5cacbb8c25e185f6239940b4
BRAVO_DRONE_5_KEYSTORE=.tmp-l2/drones/bravo/5/keystore.json


[fund/bravo] funding 5 drones with 1000000000000000000 wei STRK + ETH each...
  [1/5] 0x06d4bfc6c29f574936c768c3c44e5e7e7d7eea4c486ae056132f734ad736d64d... OK
  [2/5] 0x001baabf368b1244e017d625d2269f9842c3168955c7ecacfa4b777241b3db86... OK
  [3/5] 0x00d0b89bcb4d9be82c90dd2aceeadf852811753c9be47017007d950c876b7e63... OK
  [4/5] 0x073fa2e755625f82d488cc844978b90f436960665c03176340dc08428a98595c... OK
  [5/5] 0x016140ddc4195222fba28e8cae0b864d6052c2621dea0d228c02002f84850a41... OK

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ [200~./scripts/register-missions.sh --swarm both
bash: [200~./scripts/register-missions.sh: No such file or directory

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/register-missions.sh --swarm both

[register/alpha] mission 1 on Registry 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/alpha]   convoy_protocol L2 addr: 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
[register/alpha]   drones: 0x0255362e1f13153640f42792dd4f6116db496f3275e29c60acfb48eb1ac0be23 0x01780ad5224e90988a47fb3ced917d6b1619e25ab360f79988353d28aa1e324f 0x049cde5c76b9e36d72ac86ad3c2f835211e554f84fbc39e1f76117f32d4e4737 0x00818f630c2acc57591920e954e8000e8825b9e3286a6b5bc9623168710113ef 0x0243f3cb04a683990b3c59033a46031d0d4c00083cd688bd3b19f81fe15edce2
[register/alpha] step 1a: Registry.setConvoyProtocolL2(1, 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8)
blobGasPrice         
blobGasUsed          
to                   0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/alpha] step 1b: Verifier.setConvoyProtocolL2(1, 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8)
blobGasPrice         
blobGasUsed          
to                   0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
[register/alpha] step 2: Registry.deploy(1, spec, drones, 1700000000)
[register/alpha]   → also fires StarknetCoreStub.sendMessageToL2(...) for L1→L2 open_mission
blobGasPrice         
blobGasUsed          
to                   0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/alpha] OK

[register/bravo] mission 2 on Registry 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/bravo]   convoy_protocol L2 addr: 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
[register/bravo]   drones: 0x06d4bfc6c29f574936c768c3c44e5e7e7d7eea4c486ae056132f734ad736d64d 0x001baabf368b1244e017d625d2269f9842c3168955c7ecacfa4b777241b3db86 0x00d0b89bcb4d9be82c90dd2aceeadf852811753c9be47017007d950c876b7e63 0x073fa2e755625f82d488cc844978b90f436960665c03176340dc08428a98595c 0x016140ddc4195222fba28e8cae0b864d6052c2621dea0d228c02002f84850a41
[register/bravo] step 1a: Registry.setConvoyProtocolL2(2, 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b)
blobGasPrice         
blobGasUsed          
to                   0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/bravo] step 1b: Verifier.setConvoyProtocolL2(2, 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b)
blobGasPrice         
blobGasUsed          
to                   0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
[register/bravo] step 2: Registry.deploy(2, spec, drones, 1700000000)
[register/bravo]   → also fires StarknetCoreStub.sendMessageToL2(...) for L1→L2 open_mission
blobGasPrice         
blobGasUsed          
to                   0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
[register/bravo] OK

[register] both missions anchored on L1 + L1→L2 messages queued in StarknetCoreStub
[register] (Madara won't pick them up while --l1-sync-disabled — run open-missions.sh as the dev fallback)

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/open-missions.sh

[open/alpha] opening mission 1 on convoy-madara-alpha
[open/alpha]   convoy_protocol: 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
[open/alpha]   zone: 15×8, strip_width=3
[open/alpha]   drones: 0x0255362e1f13153640f42792dd4f6116db496f3275e29c60acfb48eb1ac0be23 0x01780ad5224e90988a47fb3ced917d6b1619e25ab360f79988353d28aa1e324f 0x049cde5c76b9e36d72ac86ad3c2f835211e554f84fbc39e1f76117f32d4e4737 0x00818f630c2acc57591920e954e8000e8825b9e3286a6b5bc9623168710113ef 0x0243f3cb04a683990b3c59033a46031d0d4c00083cd688bd3b19f81fe15edce2
WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x0375666a13f185841024c6340024e30edead816db8135ebc2d6f30d9ed05812d
Waiting for transaction 0x0375666a13f185841024c6340024e30edead816db8135ebc2d6f30d9ed05812d to confirm...
Transaction not confirmed yet...
Transaction 0x0375666a13f185841024c6340024e30edead816db8135ebc2d6f30d9ed05812d confirmed
[open/alpha] OK

[open/bravo] opening mission 2 on convoy-madara-bravo
[open/bravo]   convoy_protocol: 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
[open/bravo]   zone: 20×8, strip_width=4
[open/bravo]   drones: 0x06d4bfc6c29f574936c768c3c44e5e7e7d7eea4c486ae056132f734ad736d64d 0x001baabf368b1244e017d625d2269f9842c3168955c7ecacfa4b777241b3db86 0x00d0b89bcb4d9be82c90dd2aceeadf852811753c9be47017007d950c876b7e63 0x073fa2e755625f82d488cc844978b90f436960665c03176340dc08428a98595c 0x016140ddc4195222fba28e8cae0b864d6052c2621dea0d228c02002f84850a41
WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x01a0091d8aceff184719e4a363df17a3442de075b81448b81d5db83b4b81d540
Waiting for transaction 0x01a0091d8aceff184719e4a363df17a3442de075b81448b81d5db83b4b81d540 to confirm...
Transaction not confirmed yet...
Transaction 0x01a0091d8aceff184719e4a363df17a3442de075b81448b81d5db83b4b81d540 confirmed
[open/bravo] OK

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ python3 scripts/generate-mission.py --scenario both-safe --output-dir .tmp-l2/missions/
[generate-mission] scenario=both-safe, seed=42
[generate-mission] all 10 drones SAFE -> both swarms complete -> convoy ADVANCES
  .tmp-l2\missions\both-safe\alpha_1.json: n_cells=24 cov=1000/1000 max_p=6441 elapsed=171s
  .tmp-l2\missions\both-safe\alpha_2.json: n_cells=24 cov=1000/1000 max_p=5979 elapsed=171s
  .tmp-l2\missions\both-safe\alpha_3.json: n_cells=24 cov=1000/1000 max_p=6485 elapsed=171s
  .tmp-l2\missions\both-safe\alpha_4.json: n_cells=24 cov=1000/1000 max_p=6316 elapsed=171s
  .tmp-l2\missions\both-safe\alpha_5.json: n_cells=24 cov=1000/1000 max_p=6258 elapsed=171s
  .tmp-l2\missions\both-safe\bravo_1.json: n_cells=32 cov=1000/1000 max_p=6458 elapsed=227s
  .tmp-l2\missions\both-safe\bravo_2.json: n_cells=32 cov=1000/1000 max_p=6437 elapsed=227s
  .tmp-l2\missions\both-safe\bravo_3.json: n_cells=32 cov=1000/1000 max_p=6444 elapsed=227s
  .tmp-l2\missions\both-safe\bravo_4.json: n_cells=32 cov=1000/1000 max_p=6231 elapsed=227s
  .tmp-l2\missions\both-safe\bravo_5.json: n_cells=32 cov=1000/1000 max_p=6191 elapsed=227s

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$     for swarm in alpha bravo; do
        for did in 1 2 3 4 5; do
            f=.tmp-l2/missions/both-safe/${swarm}_${did}.json
            [ -f "$f" ] && ./scripts/submit-telemetry.sh $swarm $did "$f"
        done
    done

[submit/alpha/1] submitting telemetry
  mission_id:  1
  drone_id:    1
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_1.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x033fab274ae22dec680102afb4fb23b364623c6fbe019ece5dd9ab907fcd76ab
Waiting for transaction 0x033fab274ae22dec680102afb4fb23b364623c6fbe019ece5dd9ab907fcd76ab to confirm...
Transaction not confirmed yet...
Transaction 0x033fab274ae22dec680102afb4fb23b364623c6fbe019ece5dd9ab907fcd76ab confirmed

[submit/alpha/2] submitting telemetry
  mission_id:  1
  drone_id:    2
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_2.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x079255c12547d8ade4384aa986421b062b851c98f2e9544dce4456efa6733772
Waiting for transaction 0x079255c12547d8ade4384aa986421b062b851c98f2e9544dce4456efa6733772 to confirm...
Transaction not confirmed yet...
Transaction 0x079255c12547d8ade4384aa986421b062b851c98f2e9544dce4456efa6733772 confirmed

[submit/alpha/3] submitting telemetry
  mission_id:  1
  drone_id:    3
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_3.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x008e18b6cf8cee4dfb69387eb6e59ad2763670202c2fc50aa0a5e987ba4d80c7
Waiting for transaction 0x008e18b6cf8cee4dfb69387eb6e59ad2763670202c2fc50aa0a5e987ba4d80c7 to confirm...
Transaction not confirmed yet...
Transaction 0x008e18b6cf8cee4dfb69387eb6e59ad2763670202c2fc50aa0a5e987ba4d80c7 confirmed

[submit/alpha/4] submitting telemetry
  mission_id:  1
  drone_id:    4
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_4.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x051711d0f1cc8dffdeac8b08445247bf17d600434780c9490eed2cfec0528f3a
Waiting for transaction 0x051711d0f1cc8dffdeac8b08445247bf17d600434780c9490eed2cfec0528f3a to confirm...
Transaction not confirmed yet...
Transaction 0x051711d0f1cc8dffdeac8b08445247bf17d600434780c9490eed2cfec0528f3a confirmed

[submit/alpha/5] submitting telemetry
  mission_id:  1
  drone_id:    5
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_5.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x05a993656d5429824bdfb4c7603f7e8eca60a9cb4a9add7e4bbf2652dbb843a7
Waiting for transaction 0x05a993656d5429824bdfb4c7603f7e8eca60a9cb4a9add7e4bbf2652dbb843a7 to confirm...
Transaction not confirmed yet...
Error: transaction reverted: Insufficient max L1Gas: max amount: 0, actual used: 28144.

[submit/bravo/1] submitting telemetry
  mission_id:  2
  drone_id:    1
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_1.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x0264b75331eaaa6cd7cea0b1cee537eee3bc4f7e590ec22f018ed000ddc4db0c
Waiting for transaction 0x0264b75331eaaa6cd7cea0b1cee537eee3bc4f7e590ec22f018ed000ddc4db0c to confirm...
Transaction not confirmed yet...
Transaction 0x0264b75331eaaa6cd7cea0b1cee537eee3bc4f7e590ec22f018ed000ddc4db0c confirmed

[submit/bravo/2] submitting telemetry
  mission_id:  2
  drone_id:    2
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_2.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x069593868ee7ff88f30c761390e52361c8e3fa677f7d82decc6e9f712ae0f4f4
Waiting for transaction 0x069593868ee7ff88f30c761390e52361c8e3fa677f7d82decc6e9f712ae0f4f4 to confirm...
Transaction not confirmed yet...
Transaction 0x069593868ee7ff88f30c761390e52361c8e3fa677f7d82decc6e9f712ae0f4f4 confirmed

[submit/bravo/3] submitting telemetry
  mission_id:  2
  drone_id:    3
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_3.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x035a84abea241b424839032bcc02f91092714f35cefd1df46893960cc0366ce2
Waiting for transaction 0x035a84abea241b424839032bcc02f91092714f35cefd1df46893960cc0366ce2 to confirm...
Transaction not confirmed yet...
Transaction 0x035a84abea241b424839032bcc02f91092714f35cefd1df46893960cc0366ce2 confirmed

[submit/bravo/4] submitting telemetry
  mission_id:  2
  drone_id:    4
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_4.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x02a54924c1c347948c19419ac1c94219bc128d52d498d857df9006d169d419a2
Waiting for transaction 0x02a54924c1c347948c19419ac1c94219bc128d52d498d857df9006d169d419a2 to confirm...
Transaction not confirmed yet...
Transaction 0x02a54924c1c347948c19419ac1c94219bc128d52d498d857df9006d169d419a2 confirmed

[submit/bravo/5] submitting telemetry
  mission_id:  2
  drone_id:    5
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_5.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x0324e9322cdc4e8d0cc0c77953912ce4ae2a3ff22fcc8b771da9f3bcbdca90eb
Waiting for transaction 0x0324e9322cdc4e8d0cc0c77953912ce4ae2a3ff22fcc8b771da9f3bcbdca90eb to confirm...
Transaction not confirmed yet...
Error: transaction reverted: Insufficient max L1Gas: max amount: 0, actual used: 28144.

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/submit-telemetry.sh alpha 5 .tmp-l2/missions/both-safe/alpha_5.json

[submit/alpha/5] submitting telemetry
  mission_id:  1
  drone_id:    5
  contract:    0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
  RPC:         http://convoy-madara-alpha:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/alpha_5.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x06bb0ff892640de6e0de9b0a46c0bbade9b50bd2a57f2edb3ad17b1df30cf154
Waiting for transaction 0x06bb0ff892640de6e0de9b0a46c0bbade9b50bd2a57f2edb3ad17b1df30cf154 to confirm...
Transaction not confirmed yet...
Transaction 0x06bb0ff892640de6e0de9b0a46c0bbade9b50bd2a57f2edb3ad17b1df30cf154 confirmed

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/submit-telemetry.sh bravo 5 .tmp-l2/missions/both-safe/bravo_5.json

[submit/bravo/5] submitting telemetry
  mission_id:  2
  drone_id:    5
  contract:    0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
  RPC:         http://convoy-madara-bravo:9944/rpc/v0.8.1
  cells_file:  .tmp-l2/missions/both-safe/bravo_5.json

WARNING: setting keystore passwords via --password or env var is generally considered insecure, as they might be stored in your shell history or other log files.
Invoke transaction: 0x03312ae7265e7dedc21964b84d7a435a5987f11bf918ce1cde82e177fbf029f2
Waiting for transaction 0x03312ae7265e7dedc21964b84d7a435a5987f11bf918ce1cde82e177fbf029f2 to confirm...
Transaction not confirmed yet...
Transaction 0x03312ae7265e7dedc21964b84d7a435a5987f11bf918ce1cde82e177fbf029f2 confirmed

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ source .tmp-l2/convoy_l2_alpha.env; source .tmp-l2/convoy_l2_bravo.env

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ curl -s -X POST http://localhost:19944/rpc/v0.8.1 -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"starknet_call\",\"params\":[{\"contract_address\":\"${CONVOY_PROTOCOL_ADDR_ALPHA}\",\"entry_point_selector\":\"${SEL}\",\"calldata\":[\"0x1\"]},\"latest\"],\"id\":1}"; echo
{"jsonrpc":"2.0","result":["0x5"],"id":1}

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ curl -s -X POST http://localhost:29944/rpc/v0.8.1 -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"starknet_call\",\"params\":[{\"contract_address\":\"${CONVOY_PROTOCOL_ADDR_BRAVO}\",\"entry_point_selector\":\"${SEL}\",\"calldata\":[\"0x2\"]},\"latest\"],\"id\":1}"; echo
{"jsonrpc":"2.0","result":["0x5"],"id":1}

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ ./scripts/relay-l2-messages.sh 

[relay/alpha] checking convoy-madara-alpha for MissionSafe events on 0x05f46c7bc54b90c4b0066d3333bd71bf4b7e928ae0f900c4758edd029b1217c8
[relay/alpha] safe_count(1) = 5 → injecting MissionSafe(1, 5) on L1
blobGasPrice         
blobGasUsed          
to                   0x5FbDB2315678afecb367f032d93F642f64180aa3
[relay/alpha] now consuming on L1 Verifier
blobGasPrice         
blobGasUsed          
to                   0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
[relay/alpha] OK — Registry.missionSafe[1] should now be true

[relay/bravo] checking convoy-madara-bravo for MissionSafe events on 0x05e726c815b4a817c1d3ccdc1aabb4ec12e2c8a29ddadaab050a62463180445b
[relay/bravo] safe_count(2) = 5 → injecting MissionSafe(2, 5) on L1
blobGasPrice         
blobGasUsed          
to                   0x5FbDB2315678afecb367f032d93F642f64180aa3
[relay/bravo] now consuming on L1 Verifier
blobGasPrice         
blobGasUsed          
to                   0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
[relay/bravo] OK — Registry.missionSafe[2] should now be true

[relay] done — commander can now call CommandLog.advance(1, 2, speed) if both swarms went SAFE

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ [200~docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
>   -c "cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 'isDualSafe(uint256,uint256)(bool)' 1 2 --rpc-url http://ship-a:8545"^C

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
  -c "cast call 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 'isDualSafe(uint256,uint256)(bool)' 1 2 --rpc-url http://ship-a:8545"
Warning: This is a nightly build of Foundry. It is recommended to use the latest stable version. To mute this warning set `FOUNDRY_DISABLE_NIGHTLY_WARNING` in your environment. 

true

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ [200~docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
>   -c "cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 'advanceCount()(uint256)' --rpc-url http://ship-a:8545"~^C

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
  -c "cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 'advanceCount()(uint256)' --rpc-url http://ship-a:8545"
Warning: This is a nightly build of Foundry. It is recommended to use the latest stable version. To mute this warning set `FOUNDRY_DISABLE_NIGHTLY_WARNING` in your environment. 

0

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest -c "\
  cast send 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 \
    'advance(uint256,uint256,uint256)' 1 2 100 \
    --rpc-url http://ship-a:8545 \
    --private-key 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356 \
    --legacy"
Warning: This is a nightly build of Foundry. It is recommended to use the latest stable version. To mute this warning set `FOUNDRY_DISABLE_NIGHTLY_WARNING` in your environment. 


blockHash            0x9afcfe499c967fd9093b55e2d696d3e2e1d260755315c1f721be468a581f13fe
blockNumber          38
contractAddress      
cumulativeGasUsed    187200
effectiveGasPrice    3007453892
from                 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
gasUsed              187200
logs                 [{"address":"0xcf7ed3acca5a467e9e704c703e8d87f634fb0fc9","topics":["0xdfeb5c7a869ed6b154918d974855cb522875bde79d345921390993c0e43dbd73","0x0000000000000000000000000000000000000000000000000000000000000026","0x0000000000000000000000000000000000000000000000000000000000000001","0x0000000000000000000000000000000000000000000000000000000000000002"],"data":"0x000000000000000000000000000000000000000000000000000000000000006400000000000000000000000014dc79964da2c08b23698b3d3cc7ca32193d9955","blockHash":"0x9afcfe499c967fd9093b55e2d696d3e2e1d260755315c1f721be468a581f13fe","blockNumber":"0x26","transactionHash":"0x241a7a02cbf13617e73d093b5ab4b829adf94292d2b6c41c78d6dcd2b3dc20c4","transactionIndex":"0x0","logIndex":"0x0","removed":false}]
logsBloom            0x04000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000040001000000000040000000000000000000000001000000040000000000000000000001000000000000000000000000000000000000000000040000000000000000000000000008000000000000000000000000000000000000000000000000000000000000004000000000000100000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000008000000000000000000000
root                 
status               1 (success)
transactionHash      0x241a7a02cbf13617e73d093b5ab4b829adf94292d2b6c41c78d6dcd2b3dc20c4
transactionIndex     0
type                 0
blobGasPrice         
blobGasUsed          
to                   0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

Henri@henryjr MINGW64 ~/Desktop/Mestrado/naval-convoy-protection (main)
$ docker run --rm --network convoy-l1 ghcr.io/foundry-rs/foundry:latest \
  -c "cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 'advanceCount()(uint256)' --rpc-url http://ship-a:8545"
Warning: This is a nightly build of Foundry. It is recommended to use the latest stable version. To mute this warning set `FOUNDRY_DISABLE_NIGHTLY_WARNING` in your environment. 

1


## Notes / flakes hit
- deploy-l2 declare→deploy race (2nd attempt works)
- 5th drone of each swarm: `Insufficient max L1Gas` → re-ran alone → OK