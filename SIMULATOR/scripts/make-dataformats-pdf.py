#!/usr/bin/env python3
"""
Generate docs/data-formats-pipeline.pdf — the end-to-end data-format chain
from raw drone telemetry to the L1 ConvoyAdvance command.

Reflects the current (2026-05, 5-drone-per-swarm, hiding-Pedersen) model:
  - safe_area_verify.cairo emits 8 public felts incl. verdict_bool
  - commitment H = hiding Pedersen-chain (cells + 252-bit nonce)
  - Verifier.SafeProofInputs is the strip-based 11-field struct
"""

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, HRFlowable,
)

OUT = "docs/data-formats-pipeline.pdf"

# Layer colours (match the webapp palette)
OFFCHAIN = colors.HexColor("#F5A623")   # amber
L2       = colors.HexColor("#4A90E2")   # blue
L1       = colors.HexColor("#D0021B")   # red
LIGHT_OFF = colors.HexColor("#FCEFD6")
LIGHT_L2  = colors.HexColor("#DCE9F9")
LIGHT_L1  = colors.HexColor("#F9DCDF")
GREY      = colors.HexColor("#666666")
DARK      = colors.HexColor("#1A1A2E")

styles = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=styles["Title"], fontSize=20, spaceAfter=4, textColor=DARK)
SUB = ParagraphStyle("SUB", parent=styles["Normal"], fontSize=10, textColor=GREY, spaceAfter=14)
H2 = ParagraphStyle("H2", parent=styles["Heading2"], fontSize=13, textColor=DARK, spaceBefore=10, spaceAfter=4)
BODY = ParagraphStyle("BODY", parent=styles["Normal"], fontSize=9, leading=12, spaceAfter=4)
SMALL = ParagraphStyle("SMALL", parent=styles["Normal"], fontSize=7.5, leading=9, textColor=GREY)
CODE = ParagraphStyle("CODE", parent=styles["Code"], fontSize=7.5, leading=9, textColor=DARK)
CELL = ParagraphStyle("CELL", parent=styles["Normal"], fontSize=7.5, leading=9)
CELLB = ParagraphStyle("CELLB", parent=styles["Normal"], fontSize=7.5, leading=9, fontName="Helvetica-Bold")

story = []


def layer_chip(text, color):
    t = Table([[Paragraph(f'<font color="white"><b>{text}</b></font>', CELL)]], colWidths=[28*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), color),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t


def stage(num, title, layer_name, layer_color, light, rows, note=None):
    """rows: list of (field, type, example) tuples."""
    head = Table(
        [[Paragraph(f'<font color="white"><b>  Stage {num}</b></font>', CELL),
          Paragraph(f'<font color="white"><b>{title}</b></font>', CELLB),
          Paragraph(f'<font color="white"><b>{layer_name}</b></font>', CELL)]],
        colWidths=[22*mm, 113*mm, 35*mm],
    )
    head.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), layer_color),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
        ("RIGHTPADDING", (2, 0), (2, 0), 6),
    ]))
    story.append(head)

    data = [[Paragraph("<b>Field</b>", CELLB), Paragraph("<b>Type</b>", CELLB), Paragraph("<b>Example / Notes</b>", CELLB)]]
    for field, typ, ex in rows:
        data.append([Paragraph(field, CODE), Paragraph(typ, CELL), Paragraph(ex, CELL)])
    tbl = Table(data, colWidths=[52*mm, 38*mm, 80*mm])
    tbl.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), light),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(tbl)
    if note:
        story.append(Paragraph(note, SMALL))
    story.append(Spacer(1, 5))
    story.append(Paragraph('<font color="#999999">▼ transforms into ▼</font>',
                           ParagraphStyle("ARR", parent=BODY, alignment=1, fontSize=8)))
    story.append(Spacer(1, 5))


# ───────────────────────── Title ─────────────────────────
story.append(Paragraph("Naval Convoy Protection", H1))
story.append(Paragraph(
    "Data-format pipeline: from raw drone telemetry to the L1 <b>ConvoyAdvance</b> command. "
    "Each stage shows the schema, the data type, and a real example value from the "
    "boot-bravo-safe proving run. Colour key: "
    '<font color="#F5A623"><b>off-chain</b></font>, '
    '<font color="#4A90E2"><b>L2 (StarkNet/Madara)</b></font>, '
    '<font color="#D0021B"><b>L1 (Geth PoA)</b></font>.', SUB))
story.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor("#DDDDDD")))
story.append(Spacer(1, 8))

# ───────────────────────── Stage 0 ─────────────────────────
stage(0, "Raw drone telemetry", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("(x, y)", "grid coords", "Per-cell position from GPS / indoor UWB. e.g. (3, 5)"),
    ("p_contact", "probability", "Hostile-contact likelihood from on-board CV/radar, 0.00-1.00"),
    ("t", "unix seconds", "NTP-synced timestamp per observation. e.g. 1700000340"),
    ("bearing, heading, signal_strength", "sensor", "Richer telemetry; NOT used by the proof, stays on drone"),
], note="Physical sensor readings. Only (x, y, p_contact, t) feed the proof. Bearing / heading / "
        "signal-strength are operational tradecraft that never leave the drone.")

# ───────────────────────── Stage 1 ─────────────────────────
stage(1, "Cairo program input (witness) — program_input.json", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("mission_id, drone_id", "int", "e.g. 2, 2 (bravo). Identify mission + drone-in-swarm (1..N)"),
    ("strip_x_start / _x_end", "int", "Assigned vertical strip bounds, x-axis"),
    ("strip_y_start / _y_end", "int", "Assigned strip bounds, y-axis"),
    ("strip_total_cells", "int", "Total cells in the strip (denominator for coverage)"),
    ("coverage_min", "permille", "950 = require >= 95% strip coverage"),
    ("p_min", "basis points", "7000 = reject any contact with p >= 0.70"),
    ("time_window", "seconds", "360 = mission must finish within 6 min"),
    ("ts_start, n_cells", "int", "Mission start time; number of cells swept"),
    ("cells_x[], cells_y[]", "int[]", "Parallel arrays of swept-cell coordinates"),
    ("cells_p_contact[]", "int[]", "Per-cell contact probability (basis points)"),
    ("cells_ts[]", "int[]", "Per-cell timestamps"),
    ("cells_nonce", "felt252 (252-bit)", "Random per run — makes the commitment HIDING, not just binding"),
], note="JSON witness fed to safe_area_verify.cairo. The cells_nonce is the privacy nonce: without it, "
        "H would be brute-forceable by an attacker who guessed the cells (Pedersen 1991 hiding).")

# ───────────────────────── Stage 2 ─────────────────────────
stage(2, "Hiding Pedersen commitment H (computed inside Cairo)", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("H", "felt252", "0x055d4a0e56c1875e13e8eff57589305bc5bcda38cce164d6bf2343f76c2ea427"),
], note="H = Pedersen-chain over (cells_x || cells_y || cells_p_contact || cells_ts || cells_nonce). "
        "Hiding (nonce) + binding (any cell change alters H). This is the anchor that links the L2 "
        "record, the proof, and the L1 fact to one specific cell set without revealing it.")

# ───────────────────────── Stage 3 ─────────────────────────
stage(3, "Cairo public output — 8 felts (serialize_word order)", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("[0] mission_id", "felt252", "2"),
    ("[1] drone_id", "felt252", "2 (bravo)"),
    ("[2] strip_x_start", "felt252", "Strip bound echoed so L1 can check the right strip was swept"),
    ("[3] strip_x_end", "felt252", ""),
    ("[4] strip_y_start", "felt252", ""),
    ("[5] strip_y_end", "felt252", ""),
    ("[6] verdict_bool", "felt252", "1 = SAFE (all 4 constraints held); 0 = UNSAFE"),
    ("[7] commitment_H", "felt252", "0x055d4a0e...c2ea427"),
], note="The program ALWAYS produces a valid proof — verdict_bool carries the truth. A failed mission "
        "yields a valid proof with verdict_bool = 0, so UNSAFE outcomes are recorded explicitly rather "
        "than as 'no proof at all'.")

# ───────────────────────── Stage 4 ─────────────────────────
stage(4, "L2 transaction — ConvoyProtocol.submit_commitment", "L2", L2, LIGHT_L2, [
    ("mission_id", "felt252", "Stark-curve ECDSA signed via the drone's OZ Account contract"),
    ("drone_id", "u8", "1..N (drone index in the swarm)"),
    ("commitment_H", "felt252", "0x055d4a0e...c2ea427 (from Stage 2)"),
    ("verdict_bool", "u8", "0 or 1"),
    ("proof", "felt252[]", "The STARK proof payload (or a reference), delegated to the Cairo verifier"),
], note="The drone authenticates on L2 with Stark-curve ECDSA. The contract verifies the strip bounds "
        "match the drone's assigned strip (strip_width = zone_w / n_drones) and records the verdict.")

# ───────────────────────── Stage 5 ─────────────────────────
stage(5, "L2 storage — ConvoyProtocol state", "L2", L2, LIGHT_L2, [
    ("MissionSpec", "struct", "zone_x, zone_y, zone_w, zone_h, n_drones, strip_width"),
    ("StripBounds", "struct", "x_start, x_end, y_start, y_end (per drone, derived from zone)"),
    ("verdicts", "Map((mid,drone)→u8)", "PENDING / SAFE / UNSAFE per drone"),
    ("commitments", "Map((mid,drone)→felt252)", "H_i per drone (hiding)"),
], note="L2 is the convoy's private operational ledger — readable by the convoy via Pathfinder, NOT "
        "exposed to L1. When all N drones are SAFE, the contract emits an L1-bound message.")

# ───────────────────────── Stage 6 ─────────────────────────
stage(6, "Stone STARK proof — proof.json", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("proof body", "JSON ~800 KB", "Merkle roots + FRI commitments + OODS evals + query answers"),
    ("layout", "string", "starknet (Cairo VM layout 6)"),
    ("n_steps", "int", "65536 (Cairo VM trace length)"),
    ("(raw cells)", "—", "ABSENT: cells were the private witness, never in the proof"),
], note="cpu_air_prover output. ~802 KB for our run. Passed cpu_air_verifier off-chain "
        "(verification: PASSED). Commits to the execution TRACE, not the inputs.")

# ───────────────────────── Stage 7 ─────────────────────────
stage(7, "EVM-adapted proof — evm_proof.json", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("annotated proof", "JSON ~860 KB", "stark_evm_adapter gen-annotated-proof output"),
    ("proof_hex", "hex", "Serialized proof bytes"),
    ("public_input", "object", "memory_segments, public_memory, n_steps"),
], note="The annotated form the splitter consumes. Re-encodes the Stone proof into EVM-friendly "
        "structure without changing what's proved.")

# ───────────────────────── Stage 8 ─────────────────────────
stage(8, "Split contract args — main_proof_contract_args.json", "OFF-CHAIN", OFFCHAIN, LIGHT_OFF, [
    ("proof_params", "uint256[~12]", "FRI configuration (n_queries, layer sizes, PoW bits)"),
    ("proof", "uint256[~690]", "The STARK proof body as field elements"),
    ("task_metadata", "uint256[~1]", "Per-task program-hash metadata"),
    ("cairo_aux_input", "uint256[~30]", "Cairo public input (programHash, outputHash, z, alpha, ...)"),
    ("cairo_verifier_id", "uint256", "6 (layout 6)"),
], note="Produced by stark_evm_adapter's split_fri_merkle_statements(). These four arrays are exactly "
        "what Verifier.registerSafeProof accepts; cairo_verifier_id is stored immutably on the Verifier.")

story.append(PageBreak())

# ───────────────────────── Stage 9 ─────────────────────────
stage(9, "L1 call — Verifier.registerSafeProof(SafeProofInputs, 4 arrays)", "L1", L1, LIGHT_L1, [
    ("programHash", "bytes32", "0xcc28abddd73ffdbb3b39b9f55da9ac0ad1bff802592ac694586137ee964c5215"),
    ("outputHash", "bytes32", "0xd8c56e2c4e4826426c446b712170944096b8992cf54ede3f2e63238624454f3c"),
    ("missionId", "uint256", "2"),
    ("droneIndex", "uint8", "2 (1..nDrones)"),
    ("stripXStart / stripXEnd", "uint32", "Strip bounds, re-asserted on L1"),
    ("stripYStart / stripYEnd", "uint32", ""),
    ("verdictBool", "uint8", "1 = SAFE"),
    ("commitment", "bytes32", "0x055d4a0e...c2ea427 (H_i)"),
    ("nSteps", "uint256", "65536"),
    ("+ proofParams, proof, taskMetadata, cairoAuxInput", "uint256[] x4", "From Stage 8"),
], note="Submitted by the relay ship (Stark-curve on L2, but secp256k1 here on L1). felt252 values "
        "widen to uint256; the 252-bit hashes map to bytes32. The relay-whitelist gate checks msg.sender.")

# ───────────────────────── Stage 10 ─────────────────────────
stage(10, "L1 fact registration (inside GpsStatementVerifier + Verifier)", "L1", L1, LIGHT_L1, [
    ("factHash", "bytes32", "0x6b2b9b235356c61ec2e87e59ae6c175fbd851623edb8c40fb3b692f29852f137"),
    ("formula", "keccak256", "keccak256(abi.encodePacked(programHash, outputHash))"),
    ("verifiedFacts[factHash]", "bool", "true after the real STARK math passes on-chain"),
], note="The GpsStatementVerifier validates proofParams/proof/taskMetadata/cairoAuxInput against the "
        "layout-6 CpuFrilessVerifier, then registers the fact. Verifier.sol re-asserts the thresholds "
        "as defence-in-depth before writing the verdict.")

# ───────────────────────── Stage 11 ─────────────────────────
stage(11, "L1 verdict — Registry.setVerdict", "L1", L1, LIGHT_L1, [
    ("verdict[missionId][droneIndex]", "bool/u8", "SAFE, written only by the bound Verifier"),
    ("MissionDeployed / VerdictSet", "event", "Indexed by missionId + droneIndex for relay subscription"),
    ("MissionSafe", "event", "Emitted when ALL drones in the swarm are SAFE"),
], note="Registry is the verdict ledger. Only the Verifier may call setVerdict, and only after a "
        "successful proof. Ship D's commander orchestrator watches for the all-SAFE condition.")

# ───────────────────────── Stage 12 ─────────────────────────
stage(12, "L1 ADVANCE — CommandLog.advance", "L1", L1, LIGHT_L1, [
    ("advance(alphaMissionId, bravoMissionId, speed)", "call", "Signed by the IMMUTABLE commander key (ship D)"),
    ("dual-SAFE check", "require", "Both lanes' verdicts must be SAFE in Registry"),
    ("ConvoyAdvance", "event", "(blockNumber, alphaMissionId, bravoMissionId, speed, commander)"),
], note="The terminal step. msg.sender must equal the immutable commander address. On success, "
        "ConvoyAdvance fires and all six ships observe it on the shared L1 chain — the convoy advances.")

# ───────────────────────── Type-transition summary ─────────────────────────
story.append(Spacer(1, 6))
story.append(Paragraph("Type transitions across the layers", H2))
tt = [
    [Paragraph("<b>Concept</b>", CELLB), Paragraph("<b>Off-chain / Cairo</b>", CELLB),
     Paragraph("<b>L2 (StarkNet)</b>", CELLB), Paragraph("<b>L1 (EVM)</b>", CELLB)],
    [Paragraph("field element", CELL), Paragraph("felt252 (252-bit)", CODE),
     Paragraph("felt252", CODE), Paragraph("uint256", CODE)],
    [Paragraph("hash / commitment", CELL), Paragraph("felt252 (Pedersen)", CODE),
     Paragraph("felt252", CODE), Paragraph("bytes32", CODE)],
    [Paragraph("small ints (coords)", CELL), Paragraph("felt (range-checked)", CODE),
     Paragraph("u8 / u16 / u32 / u64", CODE), Paragraph("uint8 / uint32", CODE)],
    [Paragraph("verdict", CELL), Paragraph("felt (0/1)", CODE),
     Paragraph("u8 (PENDING/SAFE/UNSAFE)", CODE), Paragraph("uint8 / bool", CODE)],
    [Paragraph("signature", CELL), Paragraph("— (witness)", CODE),
     Paragraph("Stark-curve ECDSA", CODE), Paragraph("secp256k1 ECDSA", CODE)],
    [Paragraph("hash function", CELL), Paragraph("Pedersen (commitment)", CODE),
     Paragraph("Pedersen / Poseidon", CODE), Paragraph("Keccak-256", CODE)],
]
ttbl = Table(tt, colWidths=[35*mm, 45*mm, 45*mm, 45*mm])
ttbl.setStyle(TableStyle([
    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#EEEEEE")),
    ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ("TOPPADDING", (0, 0), (-1, -1), 3),
    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ("LEFTPADDING", (0, 0), (-1, -1), 4),
]))
story.append(ttbl)
story.append(Spacer(1, 8))
story.append(Paragraph(
    "<b>The privacy boundary is between L2 and L1.</b> The raw cells live off-chain and on the "
    "convoy's private L2; only the proof, the commitment H, the strip bounds, and the verdict "
    "cross to L1. An observer of L1 learns the verdict and the strip that was cleared, but never "
    "the sweep pattern, the per-cell contact probabilities, or any sensor tradecraft.", BODY))

doc = SimpleDocTemplate(OUT, pagesize=A4,
                        topMargin=14*mm, bottomMargin=14*mm,
                        leftMargin=14*mm, rightMargin=14*mm,
                        title="Naval Convoy — Data Format Pipeline")
doc.build(story)
print(f"WROTE {OUT}")
