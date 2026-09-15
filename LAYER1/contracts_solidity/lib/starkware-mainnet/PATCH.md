# Naval-convoy adaptation of starkex-contracts

This is a vendored copy of `starkware-libs/starkex-contracts` (mainnet master)
with **one documented modification** to make the StarkWare Solidity verifier
interoperate with the Stone prover binary that ships in
`zksecurity/stone-cli v0.2.0`.

## TL;DR

```diff
- COMMITMENT_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000
+ COMMITMENT_MASK = 0x000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
```

Single constant flip in `starkware/solidity/verifier/MerkleVerifier.sol`.
Propagates by inheritance to every call site in the layout-6 verifier.

## Why

The mask selects which 160 bits of a `keccak256` output are kept when a
Merkle / FRI commitment is truncated. The two halves of the canonical
on-chain verification stack disagree about which 160 bits to keep:

| Component                                | Side  | Bits kept |
|------------------------------------------|-------|-----------|
| `starkware-libs/starkex-contracts` master | Solidity | HIGH 160 (`& 0xFF…FF000…000`) |
| `baking-bad/stone-prover` (shipped via zksecurity/stone-cli) | C++ | LOW 160 (`MaskedHash<Keccak256, 20, IsMsb=false>`) |

If a Merkle root is committed with one alignment and verified with the
other, every internal node in the tree-walk diverges and the verifier
reverts with `INVALID_MERKLE_PROOF` at `MerkleStatementContract.verifyMerkle()`.

## Why not patch the prover instead?

Three options were on the table:

1. **Patch the prover** to use `IsMsb=true` — requires rebuilding the
   Stone prover C++ project (Bazel + Abseil + gflags + glog + gmp +
   Boost), maintaining a fork that diverges from both upstream
   `starkware-libs/stone-prover` and the `baking-bad` fork that
   stone-cli depends on.
2. **Patch the verifier mask** (this option) — one Solidity constant.
3. **Post-hoc byte shift in the adapter** — mathematically impossible.
   Tree-internal hashes are baked in at proof-creation time; shifting
   only the bytes you submit does not change the bytes the prover
   already hashed. See the discussion in the project notes.

Option 2 was chosen because:

- It is a 4-byte git diff
- It is reversible without rebuilding any toolchain
- It is symmetric: changing the mask updates all three on-chain
  consumers (Merkle internal nodes, FRI coset hashing, initial trace
  Merkle leaves) automatically through inheritance
- For a thesis / dev deployment, interop with real mainnet
  GpsStatementVerifier is not a goal

## Scope of the change

Audit confirmed (`grep -rn COMMITMENT_MASK starkware/solidity/verifier/`):

```
MerkleVerifier.sol:23       declaration (PATCHED)
MerkleVerifier.sol:122      use site, inherited
FriLayer.sol:279            use site, inherited via FriLayer is MerkleVerifier
cpu/layout6/StarkVerifier.sol:364   use site, inherited via Fri → FriLayer → MerkleVerifier
```

No other 160-bit truncation patterns exist in the verifier stack.
The convoy contracts (`contracts/src/`) do not reference COMMITMENT_MASK
or perform any hash masking — they only check `gpsStatementVerifier.isValid(factHash)`
and operate at the application layer.

## Test

`contracts/test/MerkleVerifierAlignment.t.sol` asserts that hashing two
known LSB-aligned 32-byte words and applying the patched mask yields
a value matching what stone-cli's annotation file emits for the same
input — i.e. the patched mask is provably the LSB selection, not an
ad-hoc tweak.

## Rebasing onto upstream

Cherry-pick this diff onto any future upstream sync of `starkex-contracts`:

```
file:  starkware/solidity/verifier/MerkleVerifier.sol
lines: 22-46 (comment block) and 47-49 (the constant itself)
```
