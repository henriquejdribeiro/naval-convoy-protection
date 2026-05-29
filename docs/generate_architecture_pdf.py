#!/usr/bin/env python3
"""
generate_architecture_pdf.py - build docs/architecture.pdf

Produces a thesis-aligned architecture brief covering:
  - The three trust zones (L1 / L2 / L3)
  - The sealed-envelope analogy that explains the privacy posture
  - Every contract used at every layer + why we use it
  - The customisations layered on top of vanilla StarkWare/Madara
  - The current ZK posture and what is itemised as Future Work

Run:
    python3 docs/generate_architecture_pdf.py
"""
from __future__ import annotations

from pathlib import Path

from fpdf import FPDF

DOCS_DIR = Path(__file__).resolve().parent
OUT_PDF  = DOCS_DIR / "architecture.pdf"

# ── Windows TTFs (TrueType so fpdf2 can embed and shape Unicode) ───────
FONT_REG   = "C:/Windows/Fonts/calibri.ttf"
FONT_BOLD  = "C:/Windows/Fonts/calibrib.ttf"
FONT_IT    = "C:/Windows/Fonts/calibrii.ttf"
FONT_MONO  = "C:/Windows/Fonts/consola.ttf"


class ArchPDF(FPDF):
    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("body", "I", 9)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, "Naval Convoy Protection - System Architecture", align="L")
        self.set_text_color(0, 0, 0)
        self.ln(10)

    def footer(self):
        self.set_y(-12)
        self.set_font("body", "I", 8)
        self.set_text_color(120, 120, 120)
        self.cell(0, 8, f"- {self.page_no()} -", align="C")
        self.set_text_color(0, 0, 0)

    # ── helpers ────────────────────────────────────────────────────────
    def h1(self, text: str) -> None:
        self.ln(2)
        self.set_font("body", "B", 18)
        self.set_text_color(20, 30, 80)
        self.multi_cell(0, 9, text)
        self.set_text_color(0, 0, 0)
        self.ln(2)

    def h2(self, text: str) -> None:
        self.ln(4)
        self.set_font("body", "B", 14)
        self.set_text_color(20, 30, 80)
        self.multi_cell(0, 7, text)
        self.set_text_color(0, 0, 0)
        self.ln(1)

    def h3(self, text: str) -> None:
        self.ln(2)
        self.set_font("body", "B", 11)
        self.multi_cell(0, 6, text)
        self.ln(1)

    def para(self, text: str) -> None:
        self.set_font("body", "", 10.5)
        self.multi_cell(0, 5.5, text, align="L")
        self.ln(1.5)

    def italic(self, text: str) -> None:
        self.set_font("body", "I", 10.5)
        self.multi_cell(0, 5.5, text, align="L")
        self.ln(1.5)

    def bullet(self, text: str) -> None:
        self.set_font("body", "", 10.5)
        # indent bullet
        left = self.l_margin
        self.set_x(left + 4)
        self.cell(4, 5.5, "-")
        # remaining width
        avail = self.w - self.r_margin - self.get_x()
        self.multi_cell(avail, 5.5, text, align="L")
        self.ln(0.5)

    def code(self, text: str) -> None:
        self.set_font("mono", "", 9)
        self.set_fill_color(245, 245, 248)
        # Use multi_cell with a fill for code blocks
        for line in text.splitlines() or [""]:
            self.cell(0, 5, "  " + line, fill=True, new_x="LMARGIN", new_y="NEXT")
        self.set_font("body", "", 10.5)
        self.ln(1.5)

    def kv_table(self, rows: list[tuple[str, str]], left_w: float = 55) -> None:
        """Two-column key/value table with wrapped right column."""
        full_w = self.w - self.l_margin - self.r_margin
        right_w = full_w - left_w
        line_h = 5.2
        for k, v in rows:
            # Compute the height needed for the right cell
            self.set_font("body", "", 10)
            # split lines to count rows
            lines = self.multi_cell(right_w, line_h, v, dry_run=True, output="LINES")
            h = line_h * max(1, len(lines))
            x0, y0 = self.get_x(), self.get_y()
            # Page-break check
            if y0 + h > self.h - self.b_margin:
                self.add_page()
                x0, y0 = self.get_x(), self.get_y()
            # Left cell
            self.set_font("body", "B", 10)
            self.set_fill_color(235, 238, 248)
            self.multi_cell(left_w, h, k, border=1, fill=True,
                            new_x="RIGHT", new_y="TOP",
                            max_line_height=line_h)
            # Right cell
            self.set_font("body", "", 10)
            self.set_xy(x0 + left_w, y0)
            self.multi_cell(right_w, line_h, v, border=1, align="L",
                            new_x="LMARGIN", new_y="NEXT",
                            max_line_height=line_h)
        self.ln(2)


# ── ASCII normalisation: keep PDF rendering crisp without Unicode glyphs
def n(s: str) -> str:
    repl = {
        "->": "->",  "→": "->", "←": "<-",
        "≥": ">=",  "≤": "<=", "≠": "!=",
        "·": ".",   "•": "-",
        "—": " - ", "–": "-",  "…": "...",
        "“": "\"", "”": "\"", "‘": "'", "’": "'",
        "α": "alpha", "β": "bravo",
        "§": "Sec.",
        "✓": "[OK]", "✗": "[X]",
        "└": "+", "├": "+", "│": "|", "─": "-",
        "×": "x",
    }
    out = s
    for k, v in repl.items():
        out = out.replace(k, v)
    return out


def build() -> None:
    pdf = ArchPDF(format="A4")
    pdf.set_margins(left=18, top=18, right=18)
    pdf.set_auto_page_break(auto=True, margin=15)

    # Register fonts (TTF + style variants for bold/italic/mono)
    pdf.add_font("body", "",  FONT_REG)
    pdf.add_font("body", "B", FONT_BOLD)
    pdf.add_font("body", "I", FONT_IT)
    pdf.add_font("mono", "",  FONT_MONO)

    # ── COVER ──────────────────────────────────────────────────────────
    pdf.add_page()
    pdf.ln(40)
    pdf.set_font("body", "B", 24)
    pdf.set_text_color(20, 30, 80)
    pdf.multi_cell(0, 11, n("Naval Convoy Protection"))
    pdf.ln(2)
    pdf.set_font("body", "B", 16)
    pdf.set_text_color(50, 60, 100)
    pdf.multi_cell(0, 9, n("Architecture, Layers, and Contracts"))
    pdf.ln(6)
    pdf.set_font("body", "I", 12)
    pdf.set_text_color(80, 80, 80)
    pdf.multi_cell(0, 7, n(
        "Three trust zones - off-chain drones, a sovereign Cairo L2, and an "
        "Ethereum-compatible settlement L1 - composed so that on-chain "
        "settlement reveals only sealed commitments and verified affidavits, "
        "never the underlying drone telemetry."
    ))
    pdf.ln(20)
    pdf.set_text_color(0, 0, 0)
    pdf.set_font("body", "", 11)
    pdf.multi_cell(0, 6, n(
        "This document accompanies the thesis defence. It covers the three "
        "trust zones, the customisations applied on top of vanilla StarkWare "
        "and Madara stacks, every contract used at every layer with the "
        "rationale for using it, the current security posture (sound, "
        "complete, hiding+binding commitments, non-ZK proof transcript), and "
        "the gaps itemised as Future Work."
    ))
    pdf.ln(80)
    pdf.set_font("mono", "", 9)
    pdf.set_text_color(120, 120, 120)
    pdf.cell(0, 5, "docs/architecture.pdf - generated from generate_architecture_pdf.py")
    pdf.set_text_color(0, 0, 0)

    # ── 1. OVERVIEW ────────────────────────────────────────────────────
    pdf.add_page()
    pdf.h1(n("1. System Overview"))
    pdf.para(n(
        "Two swarms of five drones each (Alpha and Bravo) sweep a SAFE_AREA "
        "ahead of a naval convoy. Each drone must prove to the convoy "
        "commander that its assigned strip of the area is safe before the "
        "convoy is allowed to advance through it. Proving is done with "
        "zk-STARKs over the Cairo CPU; the proof is verified on-chain by "
        "StarkWare's GpsStatementVerifier embedded in our Geth L1."
    ))
    pdf.para(n(
        "The convoy advance order is gated on a dual-mission SAFE flag: "
        "both Alpha and Bravo missions must aggregate five SAFE drone "
        "proofs each before the commander key can post the advance order. "
        "The cryptographic gate does not auto-fire - the commander always "
        "triggers explicitly (Pattern B). The commander key is immutable "
        "by design: fail-closed semantics, no rotation path on-chain."
    ))

    pdf.h2(n("1.1 The three trust zones"))
    pdf.kv_table([
        ("L3 - Off-chain (drone)", n(
            "Runs ArduPilot/Pixhawk flight software, sensors, the predicate "
            "Cairo program (safe_area_verify.cairo), and the Stone prover. "
            "Holds the full witness: raw cell positions, threat probabilities, "
            "timestamps, and the secret nonce. Nothing outside this zone ever "
            "sees the raw cells."
        )),
        ("L2 - Madara (Cairo rollup)", n(
            "Sovereign rollup we operate. Mirrors the convoy state, runs the "
            "Cairo Verifier for inner-proof recursion, derives each drone's "
            "strip from the mission spec, and Pedersen-chains the five "
            "commitments into a single aggregate when a swarm completes. "
            "Audit-capable because we own the sequencer."
        )),
        ("L1 - Geth (Ethereum-compatible)", n(
            "Settlement layer. Holds the canonical mission specs, the per-drone "
            "verdicts, the mission-level SAFE flag, and the convoy advance "
            "ledger. Delegates STARK math to StarkWare's audited mainnet "
            "verifier stack vendored under contracts/lib/starkware-mainnet/. "
            "Sees only commitments and proofs, never raw cells."
        )),
    ])

    # ── 2. PRIVACY POSTURE / ENVELOPE ANALOGY ─────────────────────────
    pdf.h1(n("2. Privacy Posture - The Sealed Envelope Analogy"))
    pdf.para(n(
        "The system is sound and complete (STARK guarantees), with an "
        "application-level hiding+binding commitment over the drone's cells. "
        "Strict transcript-level zero-knowledge requires Sec.5 trace-blinding "
        "(Ben-Sasson 2018) which no production Cairo prover currently ships "
        "by default - that gap is itemised as Future Work."
    ))

    pdf.h2(n("2.1 The cast"))
    pdf.kv_table([
        ("Patrol log", n(
            "The drone's witness - raw cells (x,y), per-cell p_contact and "
            "timestamps, the nonce. Lives only at L3."
        )),
        ("Sealed envelope", n(
            "The Pedersen-chain commitment H. Binding (drone cannot later "
            "open to a different log) and hiding (the secret nonce makes the "
            "seal indistinguishable from any other patrol's seal)."
        )),
        ("Notarised affidavit", n(
            "The Stone STARK proof. A small cryptographic artefact that "
            "certifies the patrol log satisfies the four SAFE_AREA rules - "
            "strip containment, coverage >= 95%, p_contact < 0.7, time "
            "window <= 6 min - without disclosing the log itself."
        )),
        ("HQ guard", n(
            "GpsStatementVerifier on L1. Checks the affidavit is "
            "mathematically authentic. Does not re-execute the Cairo program; "
            "runs O(log^2 n) field operations against the proof."
        )),
        ("Public bulletin board", n(
            "Geth L1 - Registry, Verifier, CommandLog. Anyone observing the "
            "chain sees only receipts (strip bounds, verdict, mission id, "
            "drone id), sealed envelopes (H values), affidavits (proof bytes), "
            "master seals (aggregate H), and advance orders."
        )),
        ("Interior vault", n(
            "Madara L2 - ConvoyProtocol. We own this rollup, so we can let "
            "an authorised auditor open envelopes here without anything "
            "leaving the vault. The lever exists architecturally; the audit "
            "endpoint is Future Work."
        )),
    ])

    pdf.h2(n("2.2 What is visible at each boundary"))
    pdf.kv_table([
        ("L3 - drone", n(
            "Full patrol log, nonce, raw trace, all eight public output felts."
        )),
        ("L3 -> L2 payload", n(
            "(mission_id, drone_id, H, verdict_bool, proof). Strip bounds + "
            "verdict are inside the proof's public memory. Raw cells stay at L3."
        )),
        ("L2 -> L1 payload", n(
            "Same content wrapped as an 11-field SafeProofInputs struct + "
            "the EVM-adapted proof arrays. Raw cells never cross."
        )),
        ("L1 public state", n(
            "Mission specs, per-drone records (mission id, drone idx, strip "
            "bounds, verdict, H, nSteps, timestamp, blockNumber), mission "
            "aggregate H, advance orders. No telemetry."
        )),
    ])

    pdf.h2(n("2.3 The four formal properties"))
    pdf.bullet(n("Soundness [OK] - FRI + Fiat-Shamir at ~60 bits with our prover params; mainnet uses ~80."))
    pdf.bullet(n("Completeness [OK] - the Cairo program always terminates; verdict=0 is a valid proof of NOT-SAFE."))
    pdf.bullet(n("Binding [OK] - Pedersen commitment binding under DLP on the STARK curve."))
    pdf.bullet(n("Hiding (commitment) [OK] - secret nonce makes H computationally hiding."))
    pdf.bullet(n("Zero-knowledge (proof transcript) [X] - Stone and Stwo do not blind the trace by default. Closes via Sec.5 - Future Work."))

    # ── 3. CONTRACT ENUMERATION ───────────────────────────────────────
    pdf.h1(n("3. Contracts by Layer"))

    # 3.1 L3
    pdf.h2(n("3.1 L3 - Off-chain (drone)"))
    pdf.kv_table([
        ("safe_area_verify.cairo", n(
            "Cairo 0 program. Encodes the four SAFE_AREA predicates and "
            "emits an 8-felt public output: (mission_id, drone_id, x_start, "
            "x_end, y_start, y_end, verdict_bool, H). The secret nonce is "
            "introduced via a program_input hint; the Pedersen chain over "
            "cells + nonce is computed inside the AIR so the commitment is "
            "bound to the same witness the predicates checked. Built in "
            "Cairo 0 because (a) Stone consumes that flavour, (b) cairo-vm "
            "3.2.0 (the Rust VM Stwo would force us onto) rejects arbitrary "
            "program_input hints - confirmed by the Stwo spike."
        )),
        ("Stone prover binary", n(
            "Not a contract, but the entity whose signature L1 will accept. "
            "Produces the proof in StarkWare's annotated format, ready for "
            "stark-evm-adapter conversion."
        )),
    ])

    # 3.2 L2
    pdf.h2(n("3.2 L2 - Madara (Cairo 1, sovereign rollup)"))
    pdf.kv_table([
        ("ConvoyProtocol", n(
            "cairo/convoy_protocol/src/lib.cairo - the L2 state mirror. "
            "Responsibilities: (1) #[l1_handler] open_mission bridges mission "
            "specs in from L1; (2) submit_commitment(mid, did, H, verdict, "
            "proof) accepts per-drone proofs, derives the expected strip "
            "from (zone, drone_id, strip_width) and asserts the proof's "
            "public bounds match, runs the Cairo Verifier on the inner proof, "
            "stores the per-drone H; (3) aggregate_commitment(mid) Pedersen-"
            "chains the five H values and send_message_to_l1_syscall when "
            "all drones SAFE. Lives on L2 because Cairo native Pedersen is "
            "cheap and recursive proof verification is feasible in Cairo "
            "but not in Solidity."
        )),
    ])

    # 3.3 L1 - our contracts
    pdf.h2(n("3.3 L1 - Geth - our application contracts"))
    pdf.kv_table([
        ("Registry.sol", n(
            "Single source of truth for what counts as SAFE for this convoy. "
            "Holds MissionSpec (zone dims, nDrones, stripWidth, coverageMin, "
            "pMin, timeWindow, areaHash), per-drone verdicts, the per-mission "
            "safeCount, the mission-level missionSafe flag, and the aggregate "
            "H_swarm. Commander (D's separate signing key, not the validator "
            "key) deploys specs; Verifier writes verdicts; CommandLog reads "
            "isDualSafe. Splitting state from verification lets future "
            "auditing / payout / replay-prevention contracts read the same "
            "canonical record."
        )),
        ("Verifier.sol", n(
            "Stage B of the two-stage verification model. Receives ONLY "
            "the 11-field SafeProofInputs tuple - never the proof bytes. "
            "Owns per-mission relay whitelisting (relayOf[missionId]: 1 "
            "-> ship F, 2 -> ship B), derives the expected strip from "
            "(spec, droneIndex) and rejects mismatches, asserts "
            "starkVerifier.isValid(factHash) is true (a cheap state read "
            "against GpsStatementVerifier's FactRegistry, populated by "
            "path-a-runner in Stage A), stores a ProofRecord per drone, "
            "increments safeCount, and fires Registry.setMissionSafe(mid, "
            "aggH) when the swarm completes. Per-drone calldata is ~250 "
            "bytes; the gas cost of STARK verification was already paid "
            "in Stage A."
        )),
        ("CommandLog.sol", n(
            "The advance-order ledger. The only contract bound to the "
            "commander modifier. Calls Registry.isDualSafe(alphaMid, "
            "bravoMid) and appends an AdvanceRecord. Separating this from "
            "Verifier is what makes the protocol Pattern B: D explicitly "
            "triggers the advance, the cryptographic gate does not auto-fire. "
            "Fail-closed: commander key set at deploy time, no rotation path."
        )),
        ("StarknetCoreStub.sol", n(
            "Madara's L1<->L2 bridge stub. Madara checks for it at startup. "
            "Provides the consumeMessageFromL2 + sendMessageToL2 surface "
            "ConvoyProtocol's L1 handlers need. We use a stub rather than "
            "the full StarkNet core because we operate the Madara node "
            "ourselves and only need the message-passing entry points."
        )),
        ("IStarkVerifier.sol", n(
            "Minimal interface to GpsStatementVerifier - exposes "
            "verifyProofAndRegister(...) and isValid(bytes32). Lets us swap "
            "between the real verifier and the mock without recompiling."
        )),
        ("MockStarkVerifier.sol", n(
            "Dev-only path. Accepts any proof unconditionally and registers "
            "the fact. Used by fast unit tests that do not carry real proof "
            "bytes; production / thesis-defence deployments wire the real "
            "GpsStatementVerifier instead."
        )),
        ("StarkexBarrel.sol", n(
            "Forge-compilation stub. Just imports the StarkWare mainnet "
            "Solidity files so foundry compiles them, letting "
            "DeployStarkVerifier deploy each by artifact name via "
            "vm.deployCode(File.sol:Contract). Not deployed itself."
        )),
    ])

    # 3.4 L1 - vendored StarkWare
    pdf.h2(n("3.4 L1 - Geth - vendored StarkWare mainnet stack"))
    pdf.para(n(
        "These contracts live under contracts/lib/starkware-mainnet/ and "
        "are Sourcify-verified mainnet source (byte-for-byte modulo metadata) "
        "of the contracts deployed at the well-known StarkWare addresses. "
        "We deploy our own copies via DeployStarkVerifier.s.sol so the system "
        "is self-contained on our Geth, but the source is unchanged - we are "
        "not reimplementing audited cryptographic code."
    ))
    pdf.kv_table([
        ("GpsStatementVerifier", n(
            "Public entry point. ConvoyProtocol's Verifier calls "
            "verifyProofAndRegister on this. Mainnet address "
            "0x9fb7F48dCB26b7bFA4e580b2dEFf637B13751942."
        )),
        ("CpuFrilessVerifier (layout 6)", n(
            "Cairo CPU AIR verifier for the 'starknet' layout (7 builtins: "
            "output, pedersen, range_check, ecdsa, bitwise, ec_op, poseidon). "
            "Matches stark-evm-adapter's cairoVerifierId=6 default."
        )),
        ("CairoBootloaderProgram", n(
            "Wraps task PIEs in the keccak-stripped 7-builtin bootloader so "
            "GpsStatementVerifier accepts them at "
            "registerPublicMemoryMainPage."
        )),
        ("MemoryPageFactRegistry", n(
            "Registers the public memory pages of a Cairo execution."
        )),
        ("MerkleStatementContract", n(
            "Verifies trace Merkle commitments before the main proof call."
        )),
        ("FriStatementContract", n(
            "Verifies FRI layer commitments before the main proof call."
        )),
        ("CpuOods + periodic columns", n(
            "Out-of-domain sampling evaluator and the 10 leaf polynomial "
            "contracts (CpuConstraintPoly, PedersenX/Y, EcdsaX/Y, four "
            "Poseidon round-key columns) - the math backbone of the CPU AIR. "
            "Deployed as individual contracts because their bytecode is "
            "near the EIP-170 24 KB limit."
        )),
    ])

    # ── 4. CUSTOMISATIONS ─────────────────────────────────────────────
    pdf.h1(n("4. Customisations Over Vanilla Stacks"))

    pdf.h2(n("4.1 On top of StarkWare's mainnet verifier"))
    pdf.bullet(n(
        "Bootloader hash regenerated locally. We strip the keccak builtin "
        "from cairo-bootloader's 7-builtin bootloader (scripts/strip-keccak-"
        "from-bootloader.py) and compute SIMPLE_BOOTLOADER_HASH locally; the "
        "deployed GpsStatementVerifier is constructed with that hash so the "
        "stack accepts our locally-built proofs."
    ))
    pdf.bullet(n(
        "numSecurityBits relaxed from 80 to 60 in DeployStarkVerifier.s.sol "
        "so our prover params (n_queries=16, log_n_cosets=2, "
        "proof_of_work_bits=30 -> 62 bits) clear the gate. Documented as a "
        "knob to tighten before production."
    ))
    pdf.bullet(n(
        "cairoVerifierId fixed to 6 at the array slot - matches stark-evm-"
        "adapter's hardcoded default."
    ))

    pdf.h2(n("4.2 On top of Madara"))
    pdf.bullet(n(
        "Sovereign mode - we run the sequencer ourselves so the L2 audit "
        "lever (open commitments inside the rollup without leaking to L1) "
        "is available to us."
    ))
    pdf.bullet(n(
        "L1<->L2 messaging wired through StarknetCoreStub - the smallest "
        "shim that satisfies Madara's startup contract check."
    ))
    pdf.bullet(n(
        "ConvoyProtocol does inner-proof verification via the Cairo "
        "Verifier - the recursive composition with Stone at L1 is what "
        "makes the per-drone cost cheap enough at L1: L1 verifies one outer "
        "proof attesting to L2 verifying five inner proofs per mission."
    ))

    pdf.h2(n("4.3 On top of vanilla zk-STARK posture"))
    pdf.bullet(n(
        "Application-level hiding via Pedersen-chain commitment with a "
        "secret nonce. Even without Sec.5 trace-blinding, the on-chain H "
        "is computationally hiding so the on-chain observer cannot "
        "reconstruct the cells."
    ))
    pdf.bullet(n(
        "Verdict-bool model: the Cairo program ALWAYS produces a valid "
        "proof. verdict_bool is 1 for SAFE, 0 for NOT-SAFE. This means the "
        "negative case is also auditable - you can prove your strip was "
        "found unsafe without falling off the verification path."
    ))
    pdf.bullet(n(
        "Strip-bounds gate at the Verifier - L1 derives the expected "
        "(x_start, x_end, y_start, y_end) from the spec and the drone index "
        "and asserts the proof's public bounds match. Prevents a drone "
        "from sweeping a different strip than the one assigned to it."
    ))
    pdf.bullet(n(
        "Per-mission relay whitelisting: ship F is the only relay allowed "
        "to submit Alpha proofs; ship B for Bravo. Mirror enforced in the "
        "Python submitter (submit_proof_l1.py) so wrong-key submissions "
        "fail loudly client-side."
    ))

    # ── 5. PIPELINE STATUS ────────────────────────────────────────────
    pdf.h1(n("5. Pipeline Status"))

    pdf.h2(n("5.1 What works end-to-end (code level, wired)"))
    pdf.bullet(n("L3 -> L2: drone runs safe_area_verify, Stone proof + 8-felt output. submit_commitment accepts on Madara, derives strip, runs Cairo Verifier, stores commitment."))
    pdf.bullet(n("L2 aggregation: five drones complete -> ConvoyProtocol Pedersen-chains the H values and send_message_to_l1_syscall fires."))
    pdf.bullet(n("L2 -> L1: Verifier.registerSafeProof accepts SafeProofInputs (11 fields), derives expected strip, asserts match, calls GpsStatementVerifier, stores ProofRecord, increments safeCount, fires setMissionSafe when count hits nDrones."))
    pdf.bullet(n("L1 advance: CommandLog.advance(alpha, bravo, speed) gated by Registry.isDualSafe; commander key immutable."))
    pdf.bullet(n("entrypoint.sh watcher supports per-drone runs and ALL_SAFE / ALL_UNSAFE / ALL_MIXED scenario sweeps."))

    pdf.h2(n("5.2 The Stage A / Stage B refactor"))
    pdf.para(n(
        "STARK math and application bookkeeping are now cleanly separated:"
    ))
    pdf.h3(n("Stage A - path-a-runner (Rust binary, runs against StarkWare contracts)"))
    pdf.bullet(n("Phase 1: MerkleStatementContract.verify()  -- trace decommitments"))
    pdf.bullet(n("Phase 2: FriStatementContract.verify()     -- FRI layer commits"))
    pdf.bullet(n("Phase 3: MemoryPageFactRegistry.registerContinuousMemoryPage()"))
    pdf.bullet(n("Phase 4: GpsStatementVerifier.verifyProofAndRegister()"))
    pdf.bullet(n("Effect: GpsStatementVerifier.isValid(factHash) returns true."))
    pdf.bullet(n("Contract addresses env-driven so re-deploys do not rebuild the binary."))
    pdf.h3(n("Stage B - Verifier.sol (the convoy application contract)"))
    pdf.bullet(n("Receives ONLY the 11-field SafeProofInputs tuple (no proof bytes)."))
    pdf.bullet(n("Reads starkVerifier.isValid(factHash) -- cheap state lookup."))
    pdf.bullet(n("Reverts immediately if Stage A never ran for this (program, output)."))
    pdf.bullet(n("Runs the strip-bounds gate, writes Registry.verdict, aggregates."))
    pdf.h3(n("MockStarkVerifier"))
    pdf.bullet(n("Moved out of contracts/src/ into contracts/test/. NOT compiled into production deployments."))
    pdf.bullet(n("Exposes setFactValid(factHash, true) so unit tests can simulate Stage A without running path-a-runner."))
    pdf.bullet(n("DeployL1.s.sol now refuses to deploy without STARK_VERIFIER_ADDR. Fail loud."))
    pdf.h3(n("Gas + calldata wins"))
    pdf.bullet(n("Per-drone tx to Verifier.sol shrank from ~800 KB (four EVM-adapted arrays) to ~250 bytes (11 fields)."))
    pdf.bullet(n("STARK math runs ONCE in Stage A, never duplicated in Stage B."))

    # ── 5.5 DATA SIMULATOR ────────────────────────────────────────────
    pdf.h2(n("5.3 Mission Data Simulator"))
    pdf.para(n(
        "scripts/generate-mission.py emits the per-drone program-input "
        "JSONs that drive safe_area_verify.cairo. Six scenarios are "
        "supported; the first three exercise the predicate paths inside "
        "the AIR and the last three exercise the operational handling of "
        "drone failures - the convoy-must-hold path."
    ))

    pdf.h3(n("5.3.1 Predicate scenarios"))
    pdf.kv_table([
        ("--scenario both-safe", n(
            "Every drone in both swarms sweeps a full strip with "
            "p_contact < 0.7 and elapsed <= 6 min. All 10 verdict_bool=1; "
            "safeCount hits nDrones on both missions; missionSafe flips; "
            "CommandLog.advance succeeds."
        )),
        ("--scenario both-unsafe", n(
            "alpha[3] sweeps only the first half of its strip "
            "(coverage_permille = 500 < 950) - verdict=0. bravo[3] has "
            "one cell with p_contact = 8500 > P_MIN - verdict=0. Both "
            "missions stay under nDrones; CommandLog.advance reverts."
        )),
        ("--scenario mixed", n(
            "Alpha all SAFE; bravo[4] high-contact. Single-flank failure: "
            "alpha completes but bravo does not. Tests that isDualSafe "
            "requires BOTH missions, not either-or."
        )),
    ])

    pdf.h3(n("5.3.2 Dropout (operational stress) scenarios"))
    pdf.para(n(
        "Models the cases where a drone physically cannot complete its "
        "sortie. The system must hold the convoy advance gracefully, "
        "with no crash, no off-by-one in safeCount, and a clear "
        "operational signal that a sector is uncovered."
    ))
    pdf.kv_table([
        ("--scenario alpha-dropout-vanish", n(
            "alpha[3] is reported lost. No telemetry was recovered, so "
            "no input JSON is written and no proof is generated. "
            "entrypoint.sh's ALL_VANISH trigger logs 'no telemetry for "
            "alpha3' and continues. safeCount caps at 4. missionSafe "
            "stays false. Convoy holds."
        )),
        ("--scenario alpha-dropout-midflight", n(
            "alpha[3] sweeps approximately 40% of its strip then "
            "vanishes - partial telemetry is recovered by the relay. A "
            "Cairo proof CAN still be generated against that partial "
            "cell list, verdict_bool = 0 because coverage fails the "
            ">= 95% gate. The proof lands on L1 with verdict=0; "
            "safeCount stays at 4 (the verdict=0 entry does not "
            "increment it). Convoy holds. Same on-chain outcome as "
            "vanish but with auditable partial-telemetry evidence."
        )),
        ("--scenario dual-dropout", n(
            "Worst case. alpha[3] vanishes entirely; bravo[4] disappears "
            "mid-flight. Neither mission completes. Both missions hold. "
            "The vanish_manifest.json names alpha[3] explicitly; bravo[4]'s "
            "partial proof lands with verdict=0."
        )),
    ])

    pdf.h3(n("5.3.3 vanish_manifest.json"))
    pdf.para(n(
        "Every scenario emits a vanish_manifest.json alongside the input "
        "files. Drones tagged 'vanish' have one entry each carrying "
        "(swarm, mission_id, drone_id, strip bounds, reason). "
        "entrypoint.sh announces the manifest at the top of an ALL_* run "
        "so the operator sees the sector blackouts before proving starts. "
        "Empty list when no drones vanished, so consumers can rely on "
        "the file existing."
    ))
    pdf.code(n(
        "{\n"
        "  \"scenario\": \"dual-dropout\",\n"
        "  \"summary\":  \"alpha[3] vanishes, bravo[4] midflight...\",\n"
        "  \"vanished\": [\n"
        "    {\n"
        "      \"swarm\":         \"alpha\",\n"
        "      \"mission_id\":     1,\n"
        "      \"drone_id\":       3,\n"
        "      \"strip_x_start\":  6,  \"strip_x_end\":  9,\n"
        "      \"strip_y_start\":  0,  \"strip_y_end\":  8,\n"
        "      \"reason\":         \"vanished (no telemetry recovered)\"\n"
        "    }\n"
        "  ]\n"
        "}"
    ))

    pdf.h3(n("5.3.4 End-to-end scenario runner"))
    pdf.para(n(
        "scripts/run-scenario.sh drives one scenario from generation "
        "through proving through L1 verification and asserts the on-chain "
        "outcome (Registry.isMissionSafe, Registry.safeCount, "
        "CommandLog.advance success/revert) matches what the scenario "
        "predicts. scripts/run-all-scenarios.sh runs all six and emits a "
        "pass/fail summary. Both shell scripts depend only on "
        "cast (foundry), docker, and python3 + the convoy repo. Required "
        "env: GETH_RPC_URL, REGISTRY_ADDR, COMMANDLOG_ADDR, COMMANDER_PK, "
        "STARK_VERIFIER_ADDR + the four StarkWare contract addresses for "
        "path-a-runner."
    ))

    pdf.h3(n("5.3.5 Trigger-loop integration"))
    pdf.para(n(
        "entrypoint.sh's prove_trigger watcher accepts shortcuts that "
        "map to the scenario directories one-for-one:"
    ))
    pdf.code(n(
        "ALL or ALL_SAFE         -> missions/both-safe/\n"
        "ALL_UNSAFE              -> missions/both-unsafe/\n"
        "ALL_MIXED               -> missions/mixed/\n"
        "ALL_VANISH              -> missions/alpha-dropout-vanish/\n"
        "ALL_MIDFLIGHT           -> missions/alpha-dropout-midflight/\n"
        "ALL_DUAL_DROPOUT        -> missions/dual-dropout/\n"
        "\n"
        "# Per-drone override (drive any input file):\n"
        "input=/proofs/missions/dual-dropout/alpha1_input.json tag=alpha1"
    ))

    # ── 6. FUTURE WORK ────────────────────────────────────────────────
    pdf.h1(n("6. Future Work"))
    pdf.para(n(
        "Headline item is strict zero-knowledge. The math is settled - "
        "hexens.io/blog/zk-in-starks describes the two complementary "
        "masking layers (witness masking via trace polynomials multiplied "
        "by the vanishing polynomial of the trace domain, and DEEP "
        "composition polynomial masking that injects fresh randomness "
        "into the FRI input). What is NOT settled is the engineering: "
        "the Stone Prover README does not mention zero-knowledge, "
        "blinding, masking, or witness randomisation, and ships without "
        "those techniques enabled. Stwo's README is explicit that it is "
        "non-ZK by default. Closing the gap therefore means forking a "
        "production Cairo prover and bolting on Sec.5-style blinding, "
        "or waiting for upstream. Documented as the primary Future Work "
        "item because the architecture above the prover is already "
        "ZK-ready - dropping in a ZK-Stone binary would not require any "
        "contract change."
    ))
    pdf.kv_table([
        ("Stone fork w/ Sec.5 trace-blinding", n(
            "Witness-polynomial masking (add a random low-degree poly "
            "times the vanishing poly of the trace domain) + DEEP "
            "composition masking. Removes the residual transcript-leakage "
            "gap and gives full zero-knowledge end-to-end. Prover-binary "
            "change only - every contract above stays byte-identical."
        )),
        ("Cairo 1 rewrite + Stwo migration", n(
            "Stwo's cairo-vm 3.2.0 rejects the program_input hints we rely "
            "on; safe_area_verify must be re-expressed in Cairo 1 with "
            "whitelisted hints only. Pairs naturally with the trace-"
            "blinding effort since both happen on the prover side."
        )),
        ("Poseidon-chain commitments", n(
            "Replace Pedersen-chain with Poseidon for speed inside the AIR "
            "(Poseidon is a native Cairo builtin; Pedersen is not on EVM) "
            "and to let L1 reproduce the chain on-chain if Verifier-side "
            "opening becomes desirable."
        )),
        ("Threshold/MPC nonce generation", n(
            "Distribute nonce generation across the 5 drones of a swarm "
            "(e.g. DKG) so opening requires k-of-n cooperation. Mitigates "
            "single-drone coercion."
        )),
        ("ArduPilot SITL -> Pixhawk HITL", n(
            "Hardware-in-the-loop integration so proof submission is "
            "gated by attested-enclave software on the physical drones."
        )),
        ("MQTT plane between drones and relay ships", n(
            "Operational layer - lossy radio link, replay-prevention via "
            "the L1 block number written into ConvoyAdvance events."
        )),
    ])

    # ── 7. APPENDIX - DATA SHAPES ─────────────────────────────────────
    pdf.h1(n("7. Appendix - Canonical Data Shapes"))

    pdf.h3(n("7.1 Cairo program public output (8 felts, in order)"))
    pdf.code(n(
        "[ mission_id, drone_id, x_start, x_end, y_start, y_end,\n"
        "  verdict_bool, H ]\n"
        "\n"
        " mission_id   in {1 (Alpha), 2 (Bravo)}\n"
        " drone_id     in [1, spec.nDrones]   (1..5 in our config)\n"
        " (x_start..y_end)   strip bounds in zone units\n"
        " verdict_bool in {0, 1}              1 => SAFE\n"
        " H            Pedersen-chain over cells + nonce"
    ))

    pdf.h3(n("7.2 L1 SafeProofInputs (Verifier.sol, 11 fields)"))
    pdf.code(n(
        "struct SafeProofInputs {\n"
        "    bytes32 programHash;   // keccak of safe_area_verify.cairo\n"
        "    bytes32 outputHash;    // keccak of the 8-felt output sequence\n"
        "    uint256 missionId;\n"
        "    uint8   droneIndex;    // 1..spec.nDrones\n"
        "    uint32  stripXStart;\n"
        "    uint32  stripXEnd;\n"
        "    uint32  stripYStart;\n"
        "    uint32  stripYEnd;\n"
        "    uint8   verdictBool;   // 0 or 1\n"
        "    bytes32 commitment;    // H_i (hiding Pedersen-chain)\n"
        "    uint256 nSteps;\n"
        "}"
    ))

    pdf.h3(n("7.3 Mission spec (Registry.sol)"))
    pdf.code(n(
        "struct MissionSpec {\n"
        "    bytes32 areaHash;     // Poseidon hash of polygon vertices\n"
        "    uint32  zoneX;\n"
        "    uint32  zoneY;\n"
        "    uint32  zoneW;        // 15 (Alpha) or 20 (Bravo)\n"
        "    uint32  zoneH;        // 8 (both)\n"
        "    uint8   nDrones;      // 5\n"
        "    uint32  stripWidth;   // zoneW / nDrones, exact\n"
        "    uint16  coverageMin;  // permille; 950 = 95%\n"
        "    uint16  pMin;         // bp;       7000 = 0.70\n"
        "    uint64  timeWindow;   // seconds;  360 = 6 min\n"
        "}"
    ))

    pdf.h3(n("7.4 Strip derivation formula"))
    pdf.code(n(
        "x_start = zoneX + (droneIndex - 1) * stripWidth\n"
        "x_end   = x_start + stripWidth\n"
        "y_start = zoneY\n"
        "y_end   = zoneY + zoneH\n"
        "\n"
        "Asserted both in safe_area_verify.cairo (witness check) AND in\n"
        "Verifier.sol (public-input check) - the two checks must agree\n"
        "for registerSafeProof to succeed."
    ))

    pdf.output(str(OUT_PDF))
    print(f"Wrote {OUT_PDF}")


if __name__ == "__main__":
    build()
