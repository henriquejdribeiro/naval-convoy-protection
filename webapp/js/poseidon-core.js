// ============================================================================
// poseidon-core.js — full-fidelity StarkNet Poseidon arithmetic in BigInt
// ============================================================================
// Implements the exact hades_permutation used by StarkNet (t=3, alpha=3).
// All operations are in the STARK field F_p where p = 2^251 + 17*2^192 + 1.
//
// Four public entry points:
//
//   field(x)                  — canonicalise any BigInt to F_p.
//   permutationSteps(state)   — generator that yields every sub-step of the
//                                91-round Hades permutation (ARC, S-box, MDS).
//                                Last yield is the permuted state.
//   hashSteps(a, b)           — generator for poseidon_hash(a, b). Wraps
//                                permutationSteps with the padding prelude
//                                (state = [a, b, 2]) and the output-extraction
//                                epilogue (return state[0]).
//   chainSteps(values)        — generator for a hash chain (the construction
//                                stack.js uses in computePathCommitment).
//                                acc = 0; for each v: acc = poseidon_hash(acc, v).
//
// Verified against starknet.js 6.x (Node self-test during constant generation).
// ============================================================================

import {
    POSEIDON_PRIME, POSEIDON_R_F, POSEIDON_R_P,
    POSEIDON_STATE_SIZE, POSEIDON_MDS, POSEIDON_ARK,
} from './poseidon-constants.js';

// ── felt252 arithmetic ─────────────────────────────────────────────────────

export const P = POSEIDON_PRIME;

/** Reduce any BigInt to its canonical representative in [0, P). */
export function field(x) {
    x = (x % P + P) % P;
    return x;
}

/** Modular addition. */
export function add(a, b) { return field(a + b); }

/** Modular subtraction. */
export function sub(a, b) { return field(a - b); }

/** Modular multiplication. */
export function mul(a, b) { return field(a * b); }

/** Fast modular exponentiation (square-and-multiply). */
export function pow(base, exp) {
    let result = 1n;
    base = field(base);
    while (exp > 0n) {
        if (exp & 1n) result = (result * base) % P;
        exp >>= 1n;
        base = (base * base) % P;
    }
    return result;
}

/** S-box: x^3 mod p (StarkNet Poseidon uses alpha = 3). */
export function sbox(x) { return pow(x, 3n); }

/** Multiply the 3x3 MDS matrix by the state vector in F_p. */
export function mds(state) {
    const [r0, r1, r2] = state;
    // MDS = [[3,1,1], [1,-1,1], [1,1,-2]]
    return [
        field(3n * r0 + r1 + r2),
        field(r0 - r1 + r2),
        field(r0 + r1 - 2n * r2),
    ];
}

// ── Step-yielding generators for the animation ────────────────────────────

/**
 * Yield every sub-step of the 91-round Hades permutation on a 3-element state.
 *
 * Each yielded object describes ONE observable action with enough information
 * for the widget to render a single frame.
 *
 * Event types:
 *   {type: 'init',     state}
 *   {type: 'arc',      round, isFullRound, constants, stateBefore, stateAfter}
 *   {type: 'sbox',     round, isFullRound, stateBefore, stateAfter, activeLanes}
 *   {type: 'mds',      round, isFullRound, stateBefore, stateAfter}
 *   {type: 'round-end',round, isFullRound, state}
 *   {type: 'done',     state}
 *
 * `round` is 0-indexed (0..90). The first 4 rounds are full, next 83 partial,
 * last 4 full. `isFullRound` makes this explicit so the widget can colour/label.
 */
export function* permutationSteps(initialState) {
    if (initialState.length !== POSEIDON_STATE_SIZE) {
        throw new Error('permutationSteps: state must be 3 felts, got ' + initialState.length);
    }

    let state = initialState.map(field);
    yield { type: 'init', state: [...state] };

    const HALF_FULL = POSEIDON_R_F / 2;  // 4
    let round = 0;

    // Helper: run one round and emit ARC, S-box, MDS events.
    function* doRound(state, isFullRound, round) {
        // 1. ARC: add round constants
        const arc = POSEIDON_ARK[round];
        const afterArc = state.map((v, j) => add(v, arc[j]));
        yield {
            type: 'arc', round, isFullRound,
            constants: [...arc],
            stateBefore: [...state],
            stateAfter:  [...afterArc],
        };

        // 2. S-box: full round hits all 3 lanes, partial round hits only lane 2
        let afterSbox;
        let activeLanes;
        if (isFullRound) {
            afterSbox = afterArc.map(sbox);
            activeLanes = [0, 1, 2];
        } else {
            afterSbox = [afterArc[0], afterArc[1], sbox(afterArc[2])];
            activeLanes = [2];
        }
        yield {
            type: 'sbox', round, isFullRound, activeLanes,
            stateBefore: [...afterArc],
            stateAfter:  [...afterSbox],
        };

        // 3. MDS: mix
        const afterMds = mds(afterSbox);
        yield {
            type: 'mds', round, isFullRound,
            stateBefore: [...afterSbox],
            stateAfter:  [...afterMds],
        };

        yield {
            type: 'round-end', round, isFullRound,
            state: [...afterMds],
        };
        return afterMds;
    }

    // Opening 4 full rounds
    for (let i = 0; i < HALF_FULL; i++) {
        state = yield* doRound(state, true, round++);
    }
    // 83 partial rounds
    for (let i = 0; i < POSEIDON_R_P; i++) {
        state = yield* doRound(state, false, round++);
    }
    // Closing 4 full rounds
    for (let i = 0; i < HALF_FULL; i++) {
        state = yield* doRound(state, true, round++);
    }

    yield { type: 'done', state: [...state] };
}

/**
 * poseidon_hash(a, b) — two-input hash. Spec:
 *   state = [a, b, 2]   // 2 is the domain separator for 2-input hashes
 *   run hades_permutation(state)
 *   return state[0]
 *
 * Event types:
 *   {type: 'hash-init',  a, b, separator, state}
 *   (forwards all events from permutationSteps)
 *   {type: 'hash-done',  state, output}
 */
export function* hashSteps(a, b) {
    const fa = field(a);
    const fb = field(b);
    const sep = 2n;  // domain separator for arity-2 hash
    const state = [fa, fb, sep];
    yield { type: 'hash-init', a: fa, b: fb, separator: sep, state: [...state] };

    let finalState;
    for (const evt of permutationSteps(state)) {
        yield evt;
        if (evt.type === 'done') finalState = evt.state;
    }

    yield { type: 'hash-done', state: [...finalState], output: finalState[0] };
}

/**
 * hash chain — stack.js's computePathCommitment construction.
 *   acc = 0
 *   for each v:  acc = poseidon_hash(acc, v)
 *   return acc
 *
 * Yields chain-level events plus every event from each hash invocation:
 *   {type: 'chain-init',   values}
 *   {type: 'chain-step',   stepIndex, accBefore, nextValue}
 *   (all events of a poseidon_hash(acc, v) via hashSteps)
 *   {type: 'chain-step-done', stepIndex, accAfter}
 *   {type: 'chain-done',   commitment}
 */
export function* chainSteps(values) {
    if (!Array.isArray(values) || values.length === 0) {
        throw new Error('chainSteps: values must be a non-empty array');
    }
    const vs = values.map(field);
    yield { type: 'chain-init', values: [...vs] };

    let acc = 0n;
    for (let i = 0; i < vs.length; i++) {
        yield { type: 'chain-step', stepIndex: i, accBefore: acc, nextValue: vs[i] };
        let out;
        for (const evt of hashSteps(acc, vs[i])) {
            yield evt;
            if (evt.type === 'hash-done') out = evt.output;
        }
        acc = out;
        yield { type: 'chain-step-done', stepIndex: i, accAfter: acc };
    }

    yield { type: 'chain-done', commitment: acc };
}

// ── Convenience (non-generator) helpers for validation/tests ─────────────

/** Run the full permutation and return just the final state (no events). */
export function hadesPermutation(state) {
    let v = state.map(field);
    const HALF_FULL = POSEIDON_R_F / 2;
    let round = 0;

    function doRound(state, isFullRound) {
        state = state.map((val, j) => add(val, POSEIDON_ARK[round][j]));
        if (isFullRound) state = state.map(sbox);
        else             state = [state[0], state[1], sbox(state[2])];
        state = mds(state);
        round++;
        return state;
    }

    for (let i = 0; i < HALF_FULL; i++) v = doRound(v, true);
    for (let i = 0; i < POSEIDON_R_P; i++) v = doRound(v, false);
    for (let i = 0; i < HALF_FULL; i++) v = doRound(v, true);
    return v;
}

/** One-shot poseidon_hash(a, b) — returns just the output felt. */
export function poseidonHash(a, b) {
    const final = hadesPermutation([field(a), field(b), 2n]);
    return final[0];
}

/** One-shot hash chain over an array of felts — returns the final commitment. */
export function poseidonHashChain(values) {
    let acc = 0n;
    for (const v of values) acc = poseidonHash(acc, v);
    return acc;
}

// ── Formatting helpers for the widget ─────────────────────────────────────

/** Format a felt as full hex with 0x prefix. */
export function toHex(x) {
    return '0x' + field(x).toString(16);
}

/** Format a felt as abbreviated hex like "0x3a2c…9fb1" for display. */
export function toHexShort(x, headLen = 6, tailLen = 4) {
    const hex = field(x).toString(16);
    if (hex.length <= headLen + tailLen + 1) return '0x' + hex;
    return '0x' + hex.slice(0, headLen) + '…' + hex.slice(-tailLen);
}
