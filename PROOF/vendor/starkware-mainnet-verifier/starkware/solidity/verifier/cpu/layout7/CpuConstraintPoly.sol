/*
  Copyright 2019-2024 StarkWare Industries Ltd.

  Licensed under the Apache License, Version 2.0 (the "License").
  You may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  https://www.starkware.co/open-source-license/

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions
  and limitations under the License.
*/
// ---------- The following code was auto-generated. PLEASE DO NOT EDIT. ----------
// SPDX-License-Identifier: Apache-2.0.
pragma solidity ^0.6.12;

contract CpuConstraintPoly {
    // The Memory map during the execution of this contract is as follows:
    // [0x0, 0x20) - periodic_column/pedersen/points/x.
    // [0x20, 0x40) - periodic_column/pedersen/points/y.
    // [0x40, 0x60) - periodic_column/poseidon/poseidon/full_round_key0.
    // [0x60, 0x80) - periodic_column/poseidon/poseidon/full_round_key1.
    // [0x80, 0xa0) - periodic_column/poseidon/poseidon/full_round_key2.
    // [0xa0, 0xc0) - periodic_column/poseidon/poseidon/partial_round_key0.
    // [0xc0, 0xe0) - periodic_column/poseidon/poseidon/partial_round_key1.
    // [0xe0, 0x100) - trace_length.
    // [0x100, 0x120) - offset_size.
    // [0x120, 0x140) - half_offset_size.
    // [0x140, 0x160) - initial_ap.
    // [0x160, 0x180) - initial_pc.
    // [0x180, 0x1a0) - final_ap.
    // [0x1a0, 0x1c0) - final_pc.
    // [0x1c0, 0x1e0) - memory/multi_column_perm/perm/interaction_elm.
    // [0x1e0, 0x200) - memory/multi_column_perm/hash_interaction_elm0.
    // [0x200, 0x220) - memory/multi_column_perm/perm/public_memory_prod.
    // [0x220, 0x240) - range_check16/perm/interaction_elm.
    // [0x240, 0x260) - range_check16/perm/public_memory_prod.
    // [0x260, 0x280) - range_check_min.
    // [0x280, 0x2a0) - range_check_max.
    // [0x2a0, 0x2c0) - diluted_check/permutation/interaction_elm.
    // [0x2c0, 0x2e0) - diluted_check/permutation/public_memory_prod.
    // [0x2e0, 0x300) - diluted_check/first_elm.
    // [0x300, 0x320) - diluted_check/interaction_z.
    // [0x320, 0x340) - diluted_check/interaction_alpha.
    // [0x340, 0x360) - diluted_check/final_cum_val.
    // [0x360, 0x380) - pedersen/shift_point.x.
    // [0x380, 0x3a0) - pedersen/shift_point.y.
    // [0x3a0, 0x3c0) - initial_pedersen_addr.
    // [0x3c0, 0x3e0) - initial_range_check_addr.
    // [0x3e0, 0x400) - initial_bitwise_addr.
    // [0x400, 0x420) - initial_poseidon_addr.
    // [0x420, 0x440) - trace_generator.
    // [0x440, 0x460) - oods_point.
    // [0x460, 0x520) - interaction_elements.
    // [0x520, 0x540) - composition_alpha.
    // [0x540, 0x1d40) - oods_values.
    // ----------------------- end of input data - -------------------------
    // [0x1d40, 0x1d60) - intermediate_value/cpu/decode/opcode_range_check/bit_0.
    // [0x1d60, 0x1d80) - intermediate_value/cpu/decode/opcode_range_check/bit_2.
    // [0x1d80, 0x1da0) - intermediate_value/cpu/decode/opcode_range_check/bit_4.
    // [0x1da0, 0x1dc0) - intermediate_value/cpu/decode/opcode_range_check/bit_3.
    // [0x1dc0, 0x1de0) - intermediate_value/cpu/decode/flag_op1_base_op0_0.
    // [0x1de0, 0x1e00) - intermediate_value/cpu/decode/opcode_range_check/bit_5.
    // [0x1e00, 0x1e20) - intermediate_value/cpu/decode/opcode_range_check/bit_6.
    // [0x1e20, 0x1e40) - intermediate_value/cpu/decode/opcode_range_check/bit_9.
    // [0x1e40, 0x1e60) - intermediate_value/cpu/decode/flag_res_op1_0.
    // [0x1e60, 0x1e80) - intermediate_value/cpu/decode/opcode_range_check/bit_7.
    // [0x1e80, 0x1ea0) - intermediate_value/cpu/decode/opcode_range_check/bit_8.
    // [0x1ea0, 0x1ec0) - intermediate_value/cpu/decode/flag_pc_update_regular_0.
    // [0x1ec0, 0x1ee0) - intermediate_value/cpu/decode/opcode_range_check/bit_12.
    // [0x1ee0, 0x1f00) - intermediate_value/cpu/decode/opcode_range_check/bit_13.
    // [0x1f00, 0x1f20) - intermediate_value/cpu/decode/fp_update_regular_0.
    // [0x1f20, 0x1f40) - intermediate_value/cpu/decode/opcode_range_check/bit_1.
    // [0x1f40, 0x1f60) - intermediate_value/npc_reg_0.
    // [0x1f60, 0x1f80) - intermediate_value/cpu/decode/opcode_range_check/bit_10.
    // [0x1f80, 0x1fa0) - intermediate_value/cpu/decode/opcode_range_check/bit_11.
    // [0x1fa0, 0x1fc0) - intermediate_value/cpu/decode/opcode_range_check/bit_14.
    // [0x1fc0, 0x1fe0) - intermediate_value/memory/address_diff_0.
    // [0x1fe0, 0x2000) - intermediate_value/range_check16/diff_0.
    // [0x2000, 0x2020) - intermediate_value/pedersen/hash0/ec_subset_sum/bit_0.
    // [0x2020, 0x2040) - intermediate_value/pedersen/hash0/ec_subset_sum/bit_neg_0.
    // [0x2040, 0x2060) - intermediate_value/range_check_builtin/value0_0.
    // [0x2060, 0x2080) - intermediate_value/range_check_builtin/value1_0.
    // [0x2080, 0x20a0) - intermediate_value/range_check_builtin/value2_0.
    // [0x20a0, 0x20c0) - intermediate_value/range_check_builtin/value3_0.
    // [0x20c0, 0x20e0) - intermediate_value/range_check_builtin/value4_0.
    // [0x20e0, 0x2100) - intermediate_value/range_check_builtin/value5_0.
    // [0x2100, 0x2120) - intermediate_value/range_check_builtin/value6_0.
    // [0x2120, 0x2140) - intermediate_value/range_check_builtin/value7_0.
    // [0x2140, 0x2160) - intermediate_value/bitwise/sum_var_0_0.
    // [0x2160, 0x2180) - intermediate_value/bitwise/sum_var_8_0.
    // [0x2180, 0x21a0) - intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0.
    // [0x21a0, 0x21c0) - intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_0.
    // [0x21c0, 0x21e0) - intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_0.
    // [0x21e0, 0x2200) - intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7.
    // [0x2200, 0x2220) - intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_7.
    // [0x2220, 0x2240) - intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_7.
    // [0x2240, 0x2260) - intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_3.
    // [0x2260, 0x2280) - intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_3.
    // [0x2280, 0x22a0) - intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_3.
    // [0x22a0, 0x22c0) - intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_0.
    // [0x22c0, 0x22e0) - intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_1.
    // [0x22e0, 0x2300) - intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_2.
    // [0x2300, 0x2320) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_0.
    // [0x2320, 0x2340) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_1.
    // [0x2340, 0x2360) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_2.
    // [0x2360, 0x2380) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_19.
    // [0x2380, 0x23a0) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_20.
    // [0x23a0, 0x23c0) - intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_21.
    // [0x23c0, 0x29c0) - expmods.
    // [0x29c0, 0x2d40) - domains.
    // [0x2d40, 0x2f80) - denominator_invs.
    // [0x2f80, 0x31c0) - denominators.
    // [0x31c0, 0x3280) - expmod_context.

    fallback() external {
        uint256 res;
        assembly {
            let PRIME := 0x800000000000011000000000000000000000000000000000000000000000001
            // Copy input from calldata to memory.
            calldatacopy(0x0, 0x0, /*Input data size*/ 0x1d40)
            let point := /*oods_point*/ mload(0x440)
            function expmod(base, exponent, modulus) -> result {
              let p := /*expmod_context*/ 0x31c0
              mstore(p, 0x20)                 // Length of Base.
              mstore(add(p, 0x20), 0x20)      // Length of Exponent.
              mstore(add(p, 0x40), 0x20)      // Length of Modulus.
              mstore(add(p, 0x60), base)      // Base.
              mstore(add(p, 0x80), exponent)  // Exponent.
              mstore(add(p, 0xa0), modulus)   // Modulus.
              // Call modexp precompile.
              if iszero(staticcall(not(0), 0x05, p, 0xc0, p, 0x20)) {
                revert(0, 0)
              }
              result := mload(p)
            }
            {
              // Prepare expmods for denominators and numerators.

              // expmods[0] = point^(trace_length / 2048).
              mstore(0x23c0, expmod(point, div(/*trace_length*/ mload(0xe0), 2048), PRIME))

              // expmods[1] = point^(trace_length / 1024).
              mstore(0x23e0, mulmod(
                /*point^(trace_length / 2048)*/ mload(0x23c0),
                /*point^(trace_length / 2048)*/ mload(0x23c0),
                PRIME))

              // expmods[2] = point^(trace_length / 128).
              mstore(0x2400, expmod(point, div(/*trace_length*/ mload(0xe0), 128), PRIME))

              // expmods[3] = point^(trace_length / 64).
              mstore(0x2420, mulmod(
                /*point^(trace_length / 128)*/ mload(0x2400),
                /*point^(trace_length / 128)*/ mload(0x2400),
                PRIME))

              // expmods[4] = point^(trace_length / 32).
              mstore(0x2440, mulmod(
                /*point^(trace_length / 64)*/ mload(0x2420),
                /*point^(trace_length / 64)*/ mload(0x2420),
                PRIME))

              // expmods[5] = point^(trace_length / 16).
              mstore(0x2460, mulmod(
                /*point^(trace_length / 32)*/ mload(0x2440),
                /*point^(trace_length / 32)*/ mload(0x2440),
                PRIME))

              // expmods[6] = point^(trace_length / 4).
              mstore(0x2480, expmod(point, div(/*trace_length*/ mload(0xe0), 4), PRIME))

              // expmods[7] = point^(trace_length / 2).
              mstore(0x24a0, mulmod(
                /*point^(trace_length / 4)*/ mload(0x2480),
                /*point^(trace_length / 4)*/ mload(0x2480),
                PRIME))

              // expmods[8] = point^trace_length.
              mstore(0x24c0, mulmod(
                /*point^(trace_length / 2)*/ mload(0x24a0),
                /*point^(trace_length / 2)*/ mload(0x24a0),
                PRIME))

              // expmods[9] = trace_generator^(trace_length / 64).
              mstore(0x24e0, expmod(/*trace_generator*/ mload(0x420), div(/*trace_length*/ mload(0xe0), 64), PRIME))

              // expmods[10] = trace_generator^(trace_length / 32).
              mstore(0x2500, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                PRIME))

              // expmods[11] = trace_generator^(3 * trace_length / 64).
              mstore(0x2520, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                PRIME))

              // expmods[12] = trace_generator^(trace_length / 16).
              mstore(0x2540, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(3 * trace_length / 64)*/ mload(0x2520),
                PRIME))

              // expmods[13] = trace_generator^(5 * trace_length / 64).
              mstore(0x2560, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(trace_length / 16)*/ mload(0x2540),
                PRIME))

              // expmods[14] = trace_generator^(3 * trace_length / 32).
              mstore(0x2580, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(5 * trace_length / 64)*/ mload(0x2560),
                PRIME))

              // expmods[15] = trace_generator^(7 * trace_length / 64).
              mstore(0x25a0, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(3 * trace_length / 32)*/ mload(0x2580),
                PRIME))

              // expmods[16] = trace_generator^(trace_length / 8).
              mstore(0x25c0, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(7 * trace_length / 64)*/ mload(0x25a0),
                PRIME))

              // expmods[17] = trace_generator^(9 * trace_length / 64).
              mstore(0x25e0, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(trace_length / 8)*/ mload(0x25c0),
                PRIME))

              // expmods[18] = trace_generator^(5 * trace_length / 32).
              mstore(0x2600, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(9 * trace_length / 64)*/ mload(0x25e0),
                PRIME))

              // expmods[19] = trace_generator^(11 * trace_length / 64).
              mstore(0x2620, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(5 * trace_length / 32)*/ mload(0x2600),
                PRIME))

              // expmods[20] = trace_generator^(3 * trace_length / 16).
              mstore(0x2640, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(11 * trace_length / 64)*/ mload(0x2620),
                PRIME))

              // expmods[21] = trace_generator^(13 * trace_length / 64).
              mstore(0x2660, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(3 * trace_length / 16)*/ mload(0x2640),
                PRIME))

              // expmods[22] = trace_generator^(7 * trace_length / 32).
              mstore(0x2680, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(13 * trace_length / 64)*/ mload(0x2660),
                PRIME))

              // expmods[23] = trace_generator^(15 * trace_length / 64).
              mstore(0x26a0, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(7 * trace_length / 32)*/ mload(0x2680),
                PRIME))

              // expmods[24] = trace_generator^(trace_length / 2).
              mstore(0x26c0, expmod(/*trace_generator*/ mload(0x420), div(/*trace_length*/ mload(0xe0), 2), PRIME))

              // expmods[25] = trace_generator^(19 * trace_length / 32).
              mstore(0x26e0, mulmod(
                /*trace_generator^(3 * trace_length / 32)*/ mload(0x2580),
                /*trace_generator^(trace_length / 2)*/ mload(0x26c0),
                PRIME))

              // expmods[26] = trace_generator^(5 * trace_length / 8).
              mstore(0x2700, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(19 * trace_length / 32)*/ mload(0x26e0),
                PRIME))

              // expmods[27] = trace_generator^(21 * trace_length / 32).
              mstore(0x2720, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(5 * trace_length / 8)*/ mload(0x2700),
                PRIME))

              // expmods[28] = trace_generator^(11 * trace_length / 16).
              mstore(0x2740, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(21 * trace_length / 32)*/ mload(0x2720),
                PRIME))

              // expmods[29] = trace_generator^(23 * trace_length / 32).
              mstore(0x2760, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(11 * trace_length / 16)*/ mload(0x2740),
                PRIME))

              // expmods[30] = trace_generator^(3 * trace_length / 4).
              mstore(0x2780, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(23 * trace_length / 32)*/ mload(0x2760),
                PRIME))

              // expmods[31] = trace_generator^(25 * trace_length / 32).
              mstore(0x27a0, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(3 * trace_length / 4)*/ mload(0x2780),
                PRIME))

              // expmods[32] = trace_generator^(13 * trace_length / 16).
              mstore(0x27c0, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(25 * trace_length / 32)*/ mload(0x27a0),
                PRIME))

              // expmods[33] = trace_generator^(27 * trace_length / 32).
              mstore(0x27e0, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(13 * trace_length / 16)*/ mload(0x27c0),
                PRIME))

              // expmods[34] = trace_generator^(7 * trace_length / 8).
              mstore(0x2800, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(27 * trace_length / 32)*/ mload(0x27e0),
                PRIME))

              // expmods[35] = trace_generator^(29 * trace_length / 32).
              mstore(0x2820, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(7 * trace_length / 8)*/ mload(0x2800),
                PRIME))

              // expmods[36] = trace_generator^(15 * trace_length / 16).
              mstore(0x2840, mulmod(
                /*trace_generator^(trace_length / 32)*/ mload(0x2500),
                /*trace_generator^(29 * trace_length / 32)*/ mload(0x2820),
                PRIME))

              // expmods[37] = trace_generator^(61 * trace_length / 64).
              mstore(0x2860, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(15 * trace_length / 16)*/ mload(0x2840),
                PRIME))

              // expmods[38] = trace_generator^(31 * trace_length / 32).
              mstore(0x2880, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(61 * trace_length / 64)*/ mload(0x2860),
                PRIME))

              // expmods[39] = trace_generator^(63 * trace_length / 64).
              mstore(0x28a0, mulmod(
                /*trace_generator^(trace_length / 64)*/ mload(0x24e0),
                /*trace_generator^(31 * trace_length / 32)*/ mload(0x2880),
                PRIME))

              // expmods[40] = trace_generator^(255 * trace_length / 256).
              mstore(0x28c0, expmod(/*trace_generator*/ mload(0x420), div(mul(255, /*trace_length*/ mload(0xe0)), 256), PRIME))

              // expmods[41] = trace_generator^(trace_length - 16).
              mstore(0x28e0, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 16), PRIME))

              // expmods[42] = trace_generator^(trace_length - 2).
              mstore(0x2900, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 2), PRIME))

              // expmods[43] = trace_generator^(trace_length - 4).
              mstore(0x2920, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 4), PRIME))

              // expmods[44] = trace_generator^(trace_length - 1).
              mstore(0x2940, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 1), PRIME))

              // expmods[45] = trace_generator^(trace_length - 2048).
              mstore(0x2960, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 2048), PRIME))

              // expmods[46] = trace_generator^(trace_length - 128).
              mstore(0x2980, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 128), PRIME))

              // expmods[47] = trace_generator^(trace_length - 64).
              mstore(0x29a0, expmod(/*trace_generator*/ mload(0x420), sub(/*trace_length*/ mload(0xe0), 64), PRIME))

            }

            {
              // Compute domains.

              // Denominator for constraints: 'cpu/decode/opcode_range_check/bit', 'diluted_check/permutation/step0', 'diluted_check/step'.
              // domains[0] = point^trace_length - 1.
              mstore(0x29c0,
                     addmod(/*point^trace_length*/ mload(0x24c0), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'memory/multi_column_perm/perm/step0', 'memory/diff_is_bit', 'memory/is_func', 'poseidon/poseidon/partial_rounds_state0_squaring', 'poseidon/poseidon/partial_round0'.
              // domains[1] = point^(trace_length / 2) - 1.
              mstore(0x29e0,
                     addmod(/*point^(trace_length / 2)*/ mload(0x24a0), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'range_check16/perm/step0', 'range_check16/diff_is_bit', 'pedersen/hash0/ec_subset_sum/booleanity_test', 'pedersen/hash0/ec_subset_sum/add_points/slope', 'pedersen/hash0/ec_subset_sum/add_points/x', 'pedersen/hash0/ec_subset_sum/add_points/y', 'pedersen/hash0/ec_subset_sum/copy_point/x', 'pedersen/hash0/ec_subset_sum/copy_point/y', 'poseidon/poseidon/partial_rounds_state1_squaring', 'poseidon/poseidon/partial_round1'.
              // domains[2] = point^(trace_length / 4) - 1.
              mstore(0x2a00,
                     addmod(/*point^(trace_length / 4)*/ mload(0x2480), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'cpu/decode/opcode_range_check/zero'.
              // Numerator for constraints: 'cpu/decode/opcode_range_check/bit'.
              // domains[3] = point^(trace_length / 16) - trace_generator^(15 * trace_length / 16).
              mstore(0x2a20,
                     addmod(
                       /*point^(trace_length / 16)*/ mload(0x2460),
                       sub(PRIME, /*trace_generator^(15 * trace_length / 16)*/ mload(0x2840)),
                       PRIME))

              // Denominator for constraints: 'cpu/decode/opcode_range_check_input', 'cpu/decode/flag_op1_base_op0_bit', 'cpu/decode/flag_res_op1_bit', 'cpu/decode/flag_pc_update_regular_bit', 'cpu/decode/fp_update_regular_bit', 'cpu/operands/mem_dst_addr', 'cpu/operands/mem0_addr', 'cpu/operands/mem1_addr', 'cpu/operands/ops_mul', 'cpu/operands/res', 'cpu/update_registers/update_pc/tmp0', 'cpu/update_registers/update_pc/tmp1', 'cpu/update_registers/update_pc/pc_cond_negative', 'cpu/update_registers/update_pc/pc_cond_positive', 'cpu/update_registers/update_ap/ap_update', 'cpu/update_registers/update_fp/fp_update', 'cpu/opcodes/call/push_fp', 'cpu/opcodes/call/push_pc', 'cpu/opcodes/call/off0', 'cpu/opcodes/call/off1', 'cpu/opcodes/call/flags', 'cpu/opcodes/ret/off0', 'cpu/opcodes/ret/off2', 'cpu/opcodes/ret/flags', 'cpu/opcodes/assert_eq/assert_eq', 'public_memory_addr_zero', 'public_memory_value_zero', 'poseidon/poseidon/full_rounds_state0_squaring', 'poseidon/poseidon/full_rounds_state1_squaring', 'poseidon/poseidon/full_rounds_state2_squaring', 'poseidon/poseidon/full_round0', 'poseidon/poseidon/full_round1', 'poseidon/poseidon/full_round2'.
              // domains[4] = point^(trace_length / 16) - 1.
              mstore(0x2a40,
                     addmod(/*point^(trace_length / 16)*/ mload(0x2460), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'bitwise/step_var_pool_addr', 'bitwise/partition'.
              // domains[5] = point^(trace_length / 32) - 1.
              mstore(0x2a60,
                     addmod(/*point^(trace_length / 32)*/ mload(0x2440), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'poseidon/param_0/addr_input_output_step', 'poseidon/param_1/addr_input_output_step', 'poseidon/param_2/addr_input_output_step'.
              // domains[6] = point^(trace_length / 64) - 1.
              mstore(0x2a80,
                     addmod(/*point^(trace_length / 64)*/ mload(0x2420), sub(PRIME, 1), PRIME))

              // Numerator for constraints: 'poseidon/poseidon/full_round0', 'poseidon/poseidon/full_round1', 'poseidon/poseidon/full_round2'.
              // domains[7] = point^(trace_length / 64) - trace_generator^(3 * trace_length / 4).
              mstore(0x2aa0,
                     addmod(
                       /*point^(trace_length / 64)*/ mload(0x2420),
                       sub(PRIME, /*trace_generator^(3 * trace_length / 4)*/ mload(0x2780)),
                       PRIME))

              // Denominator for constraints: 'range_check_builtin/value', 'range_check_builtin/addr_step', 'bitwise/x_or_y_addr', 'bitwise/next_var_pool_addr', 'bitwise/or_is_and_plus_xor', 'bitwise/unique_unpacking192', 'bitwise/unique_unpacking193', 'bitwise/unique_unpacking194', 'bitwise/unique_unpacking195', 'poseidon/poseidon/add_first_round_key0', 'poseidon/poseidon/add_first_round_key1', 'poseidon/poseidon/add_first_round_key2', 'poseidon/poseidon/last_full_round0', 'poseidon/poseidon/last_full_round1', 'poseidon/poseidon/last_full_round2', 'poseidon/poseidon/copy_partial_rounds0_i0', 'poseidon/poseidon/copy_partial_rounds0_i1', 'poseidon/poseidon/copy_partial_rounds0_i2', 'poseidon/poseidon/margin_full_to_partial0', 'poseidon/poseidon/margin_full_to_partial1', 'poseidon/poseidon/margin_full_to_partial2', 'poseidon/poseidon/margin_partial_to_full0', 'poseidon/poseidon/margin_partial_to_full1', 'poseidon/poseidon/margin_partial_to_full2'.
              // domains[8] = point^(trace_length / 128) - 1.
              mstore(0x2ac0,
                     addmod(/*point^(trace_length / 128)*/ mload(0x2400), sub(PRIME, 1), PRIME))

              // Numerator for constraints: 'bitwise/step_var_pool_addr'.
              // domains[9] = point^(trace_length / 128) - trace_generator^(3 * trace_length / 4).
              mstore(0x2ae0,
                     addmod(
                       /*point^(trace_length / 128)*/ mload(0x2400),
                       sub(PRIME, /*trace_generator^(3 * trace_length / 4)*/ mload(0x2780)),
                       PRIME))

              // Denominator for constraints: 'bitwise/addition_is_xor_with_and'.
              // domains[10] = (point^(trace_length / 128) - trace_generator^(trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(9 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(11 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(13 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(15 * trace_length / 64)) * domain8.
              {
                let domain := mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(trace_length / 64)*/ mload(0x24e0)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(trace_length / 32)*/ mload(0x2500)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(3 * trace_length / 64)*/ mload(0x2520)),
                        PRIME),
                      PRIME),
                    addmod(
                      /*point^(trace_length / 128)*/ mload(0x2400),
                      sub(PRIME, /*trace_generator^(trace_length / 16)*/ mload(0x2540)),
                      PRIME),
                    PRIME)
                domain := mulmod(
                  domain,
                  mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(5 * trace_length / 64)*/ mload(0x2560)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(3 * trace_length / 32)*/ mload(0x2580)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(7 * trace_length / 64)*/ mload(0x25a0)),
                        PRIME),
                      PRIME),
                    addmod(
                      /*point^(trace_length / 128)*/ mload(0x2400),
                      sub(PRIME, /*trace_generator^(trace_length / 8)*/ mload(0x25c0)),
                      PRIME),
                    PRIME),
                  PRIME)
                domain := mulmod(
                  domain,
                  mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(9 * trace_length / 64)*/ mload(0x25e0)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(5 * trace_length / 32)*/ mload(0x2600)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(11 * trace_length / 64)*/ mload(0x2620)),
                        PRIME),
                      PRIME),
                    addmod(
                      /*point^(trace_length / 128)*/ mload(0x2400),
                      sub(PRIME, /*trace_generator^(3 * trace_length / 16)*/ mload(0x2640)),
                      PRIME),
                    PRIME),
                  PRIME)
                domain := mulmod(
                  domain,
                  mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(13 * trace_length / 64)*/ mload(0x2660)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(7 * trace_length / 32)*/ mload(0x2680)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(15 * trace_length / 64)*/ mload(0x26a0)),
                        PRIME),
                      PRIME),
                    /*domains[8]*/ mload(0x2ac0),
                    PRIME),
                  PRIME)
                mstore(0x2b00, domain)
              }

              // domains[11] = point^(trace_length / 128) - trace_generator^(31 * trace_length / 32).
              mstore(0x2b20,
                     addmod(
                       /*point^(trace_length / 128)*/ mload(0x2400),
                       sub(PRIME, /*trace_generator^(31 * trace_length / 32)*/ mload(0x2880)),
                       PRIME))

              // Numerator for constraints: 'poseidon/poseidon/partial_rounds_state1_squaring'.
              // domains[12] = (point^(trace_length / 128) - trace_generator^(11 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(23 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(25 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(13 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(27 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(29 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(15 * trace_length / 16)) * domain9 * domain11.
              {
                let domain := mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(11 * trace_length / 16)*/ mload(0x2740)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(23 * trace_length / 32)*/ mload(0x2760)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(25 * trace_length / 32)*/ mload(0x27a0)),
                        PRIME),
                      PRIME),
                    addmod(
                      /*point^(trace_length / 128)*/ mload(0x2400),
                      sub(PRIME, /*trace_generator^(13 * trace_length / 16)*/ mload(0x27c0)),
                      PRIME),
                    PRIME)
                domain := mulmod(
                  domain,
                  mulmod(
                    mulmod(
                      mulmod(
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(27 * trace_length / 32)*/ mload(0x27e0)),
                          PRIME),
                        addmod(
                          /*point^(trace_length / 128)*/ mload(0x2400),
                          sub(PRIME, /*trace_generator^(7 * trace_length / 8)*/ mload(0x2800)),
                          PRIME),
                        PRIME),
                      addmod(
                        /*point^(trace_length / 128)*/ mload(0x2400),
                        sub(PRIME, /*trace_generator^(29 * trace_length / 32)*/ mload(0x2820)),
                        PRIME),
                      PRIME),
                    addmod(
                      /*point^(trace_length / 128)*/ mload(0x2400),
                      sub(PRIME, /*trace_generator^(15 * trace_length / 16)*/ mload(0x2840)),
                      PRIME),
                    PRIME),
                  PRIME)
                domain := mulmod(
                  domain,
                  mulmod(/*domains[9]*/ mload(0x2ae0), /*domains[11]*/ mload(0x2b20), PRIME),
                  PRIME)
                mstore(0x2b40, domain)
              }

              // Numerator for constraints: 'poseidon/poseidon/partial_round0'.
              // domains[13] = (point^(trace_length / 128) - trace_generator^(61 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(63 * trace_length / 64)) * domain11.
              mstore(0x2b60,
                     mulmod(
                       mulmod(
                         addmod(
                           /*point^(trace_length / 128)*/ mload(0x2400),
                           sub(PRIME, /*trace_generator^(61 * trace_length / 64)*/ mload(0x2860)),
                           PRIME),
                         addmod(
                           /*point^(trace_length / 128)*/ mload(0x2400),
                           sub(PRIME, /*trace_generator^(63 * trace_length / 64)*/ mload(0x28a0)),
                           PRIME),
                         PRIME),
                       /*domains[11]*/ mload(0x2b20),
                       PRIME))

              // Numerator for constraints: 'poseidon/poseidon/partial_round1'.
              // domains[14] = (point^(trace_length / 128) - trace_generator^(19 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(21 * trace_length / 32)) * domain12.
              mstore(0x2b80,
                     mulmod(
                       mulmod(
                         mulmod(
                           addmod(
                             /*point^(trace_length / 128)*/ mload(0x2400),
                             sub(PRIME, /*trace_generator^(19 * trace_length / 32)*/ mload(0x26e0)),
                             PRIME),
                           addmod(
                             /*point^(trace_length / 128)*/ mload(0x2400),
                             sub(PRIME, /*trace_generator^(5 * trace_length / 8)*/ mload(0x2700)),
                             PRIME),
                           PRIME),
                         addmod(
                           /*point^(trace_length / 128)*/ mload(0x2400),
                           sub(PRIME, /*trace_generator^(21 * trace_length / 32)*/ mload(0x2720)),
                           PRIME),
                         PRIME),
                       /*domains[12]*/ mload(0x2b40),
                       PRIME))

              // Denominator for constraints: 'pedersen/hash0/ec_subset_sum/bit_unpacking/last_one_is_zero', 'pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones0', 'pedersen/hash0/ec_subset_sum/bit_unpacking/cumulative_bit192', 'pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones192', 'pedersen/hash0/ec_subset_sum/bit_unpacking/cumulative_bit196', 'pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones196', 'pedersen/hash0/copy_point/x', 'pedersen/hash0/copy_point/y'.
              // domains[15] = point^(trace_length / 1024) - 1.
              mstore(0x2ba0,
                     addmod(/*point^(trace_length / 1024)*/ mload(0x23e0), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'pedersen/hash0/ec_subset_sum/zeros_tail'.
              // Numerator for constraints: 'pedersen/hash0/ec_subset_sum/booleanity_test', 'pedersen/hash0/ec_subset_sum/add_points/slope', 'pedersen/hash0/ec_subset_sum/add_points/x', 'pedersen/hash0/ec_subset_sum/add_points/y', 'pedersen/hash0/ec_subset_sum/copy_point/x', 'pedersen/hash0/ec_subset_sum/copy_point/y'.
              // domains[16] = point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              mstore(0x2bc0,
                     addmod(
                       /*point^(trace_length / 1024)*/ mload(0x23e0),
                       sub(PRIME, /*trace_generator^(255 * trace_length / 256)*/ mload(0x28c0)),
                       PRIME))

              // Denominator for constraints: 'pedersen/hash0/ec_subset_sum/bit_extraction_end'.
              // domains[17] = point^(trace_length / 1024) - trace_generator^(63 * trace_length / 64).
              mstore(0x2be0,
                     addmod(
                       /*point^(trace_length / 1024)*/ mload(0x23e0),
                       sub(PRIME, /*trace_generator^(63 * trace_length / 64)*/ mload(0x28a0)),
                       PRIME))

              // Numerator for constraints: 'pedersen/hash0/copy_point/x', 'pedersen/hash0/copy_point/y'.
              // domains[18] = point^(trace_length / 2048) - trace_generator^(trace_length / 2).
              mstore(0x2c00,
                     addmod(
                       /*point^(trace_length / 2048)*/ mload(0x23c0),
                       sub(PRIME, /*trace_generator^(trace_length / 2)*/ mload(0x26c0)),
                       PRIME))

              // Denominator for constraints: 'pedersen/hash0/init/x', 'pedersen/hash0/init/y', 'pedersen/input0_value0', 'pedersen/input0_addr', 'pedersen/input1_value0', 'pedersen/input1_addr', 'pedersen/output_value0', 'pedersen/output_addr'.
              // domains[19] = point^(trace_length / 2048) - 1.
              mstore(0x2c20,
                     addmod(/*point^(trace_length / 2048)*/ mload(0x23c0), sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'final_ap', 'final_fp', 'final_pc'.
              // Numerator for constraints: 'cpu/update_registers/update_pc/tmp0', 'cpu/update_registers/update_pc/tmp1', 'cpu/update_registers/update_pc/pc_cond_negative', 'cpu/update_registers/update_pc/pc_cond_positive', 'cpu/update_registers/update_ap/ap_update', 'cpu/update_registers/update_fp/fp_update'.
              // domains[20] = point - trace_generator^(trace_length - 16).
              mstore(0x2c40,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 16)*/ mload(0x28e0)), PRIME))

              // Denominator for constraints: 'initial_ap', 'initial_fp', 'initial_pc', 'memory/multi_column_perm/perm/init0', 'memory/initial_addr', 'range_check16/perm/init0', 'range_check16/minimum', 'diluted_check/permutation/init0', 'diluted_check/init', 'diluted_check/first_element', 'pedersen/init_addr', 'range_check_builtin/init_addr', 'bitwise/init_var_pool_addr', 'poseidon/param_0/init_input_output_addr', 'poseidon/param_1/init_input_output_addr', 'poseidon/param_2/init_input_output_addr'.
              // domains[21] = point - 1.
              mstore(0x2c60,
                     addmod(point, sub(PRIME, 1), PRIME))

              // Denominator for constraints: 'memory/multi_column_perm/perm/last'.
              // Numerator for constraints: 'memory/multi_column_perm/perm/step0', 'memory/diff_is_bit', 'memory/is_func'.
              // domains[22] = point - trace_generator^(trace_length - 2).
              mstore(0x2c80,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 2)*/ mload(0x2900)), PRIME))

              // Denominator for constraints: 'range_check16/perm/last', 'range_check16/maximum'.
              // Numerator for constraints: 'range_check16/perm/step0', 'range_check16/diff_is_bit'.
              // domains[23] = point - trace_generator^(trace_length - 4).
              mstore(0x2ca0,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 4)*/ mload(0x2920)), PRIME))

              // Denominator for constraints: 'diluted_check/permutation/last', 'diluted_check/last'.
              // Numerator for constraints: 'diluted_check/permutation/step0', 'diluted_check/step'.
              // domains[24] = point - trace_generator^(trace_length - 1).
              mstore(0x2cc0,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 1)*/ mload(0x2940)), PRIME))

              // Numerator for constraints: 'pedersen/input0_addr'.
              // domains[25] = point - trace_generator^(trace_length - 2048).
              mstore(0x2ce0,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 2048)*/ mload(0x2960)), PRIME))

              // Numerator for constraints: 'range_check_builtin/addr_step', 'bitwise/next_var_pool_addr'.
              // domains[26] = point - trace_generator^(trace_length - 128).
              mstore(0x2d00,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 128)*/ mload(0x2980)), PRIME))

              // Numerator for constraints: 'poseidon/param_0/addr_input_output_step', 'poseidon/param_1/addr_input_output_step', 'poseidon/param_2/addr_input_output_step'.
              // domains[27] = point - trace_generator^(trace_length - 64).
              mstore(0x2d20,
                     addmod(point, sub(PRIME, /*trace_generator^(trace_length - 64)*/ mload(0x29a0)), PRIME))

            }

            {
              // Prepare denominators for batch inverse.

              // denominators[0] = domains[0].
              mstore(0x2f80, /*domains[0]*/ mload(0x29c0))

              // denominators[1] = domains[3].
              mstore(0x2fa0, /*domains[3]*/ mload(0x2a20))

              // denominators[2] = domains[4].
              mstore(0x2fc0, /*domains[4]*/ mload(0x2a40))

              // denominators[3] = domains[20].
              mstore(0x2fe0, /*domains[20]*/ mload(0x2c40))

              // denominators[4] = domains[21].
              mstore(0x3000, /*domains[21]*/ mload(0x2c60))

              // denominators[5] = domains[1].
              mstore(0x3020, /*domains[1]*/ mload(0x29e0))

              // denominators[6] = domains[22].
              mstore(0x3040, /*domains[22]*/ mload(0x2c80))

              // denominators[7] = domains[2].
              mstore(0x3060, /*domains[2]*/ mload(0x2a00))

              // denominators[8] = domains[23].
              mstore(0x3080, /*domains[23]*/ mload(0x2ca0))

              // denominators[9] = domains[24].
              mstore(0x30a0, /*domains[24]*/ mload(0x2cc0))

              // denominators[10] = domains[15].
              mstore(0x30c0, /*domains[15]*/ mload(0x2ba0))

              // denominators[11] = domains[16].
              mstore(0x30e0, /*domains[16]*/ mload(0x2bc0))

              // denominators[12] = domains[17].
              mstore(0x3100, /*domains[17]*/ mload(0x2be0))

              // denominators[13] = domains[19].
              mstore(0x3120, /*domains[19]*/ mload(0x2c20))

              // denominators[14] = domains[8].
              mstore(0x3140, /*domains[8]*/ mload(0x2ac0))

              // denominators[15] = domains[5].
              mstore(0x3160, /*domains[5]*/ mload(0x2a60))

              // denominators[16] = domains[10].
              mstore(0x3180, /*domains[10]*/ mload(0x2b00))

              // denominators[17] = domains[6].
              mstore(0x31a0, /*domains[6]*/ mload(0x2a80))

            }

            {
              // Compute the inverses of the denominators into denominatorInvs using batch inverse.

              // Start by computing the cumulative product.
              // Let (d_0, d_1, d_2, ..., d_{n-1}) be the values in denominators. After this loop
              // denominatorInvs will be (1, d_0, d_0 * d_1, ...) and prod will contain the value of
              // d_0 * ... * d_{n-1}.
              // Compute the offset between the partialProducts array and the input values array.
              let productsToValuesOffset := 0x240
              let prod := 1
              let partialProductEndPtr := 0x2f80
              for { let partialProductPtr := 0x2d40 }
                  lt(partialProductPtr, partialProductEndPtr)
                  { partialProductPtr := add(partialProductPtr, 0x20) } {
                  mstore(partialProductPtr, prod)
                  // prod *= d_{i}.
                  prod := mulmod(prod,
                                 mload(add(partialProductPtr, productsToValuesOffset)),
                                 PRIME)
              }

              let firstPartialProductPtr := 0x2d40
              // Compute the inverse of the product.
              let prodInv := expmod(prod, sub(PRIME, 2), PRIME)

              if eq(prodInv, 0) {
                  // Solidity generates reverts with reason that look as follows:
                  // 1. 4 bytes with the constant 0x08c379a0 (== Keccak256(b'Error(string)')[:4]).
                  // 2. 32 bytes offset bytes (always 0x20 as far as i can tell).
                  // 3. 32 bytes with the length of the revert reason.
                  // 4. Revert reason string.

                  mstore(0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
                  mstore(0x4, 0x20)
                  mstore(0x24, 0x1e)
                  mstore(0x44, "Batch inverse product is zero.")
                  revert(0, 0x62)
              }

              // Compute the inverses.
              // Loop over denominator_invs in reverse order.
              // currentPartialProductPtr is initialized to one past the end.
              let currentPartialProductPtr := 0x2f80
              for { } gt(currentPartialProductPtr, firstPartialProductPtr) { } {
                  currentPartialProductPtr := sub(currentPartialProductPtr, 0x20)
                  // Store 1/d_{i} = (d_0 * ... * d_{i-1}) * 1/(d_0 * ... * d_{i}).
                  mstore(currentPartialProductPtr,
                         mulmod(mload(currentPartialProductPtr), prodInv, PRIME))
                  // Update prodInv to be 1/(d_0 * ... * d_{i-1}) by multiplying by d_i.
                  prodInv := mulmod(prodInv,
                                     mload(add(currentPartialProductPtr, productsToValuesOffset)),
                                     PRIME)
              }
            }

            {
              // Compute the result of the composition polynomial.

              {
              // cpu/decode/opcode_range_check/bit_0 = column0_row0 - (column0_row1 + column0_row1).
              let val := addmod(
                /*column0_row0*/ mload(0x540),
                sub(
                  PRIME,
                  addmod(/*column0_row1*/ mload(0x560), /*column0_row1*/ mload(0x560), PRIME)),
                PRIME)
              mstore(0x1d40, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_2 = column0_row2 - (column0_row3 + column0_row3).
              let val := addmod(
                /*column0_row2*/ mload(0x580),
                sub(
                  PRIME,
                  addmod(/*column0_row3*/ mload(0x5a0), /*column0_row3*/ mload(0x5a0), PRIME)),
                PRIME)
              mstore(0x1d60, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_4 = column0_row4 - (column0_row5 + column0_row5).
              let val := addmod(
                /*column0_row4*/ mload(0x5c0),
                sub(
                  PRIME,
                  addmod(/*column0_row5*/ mload(0x5e0), /*column0_row5*/ mload(0x5e0), PRIME)),
                PRIME)
              mstore(0x1d80, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_3 = column0_row3 - (column0_row4 + column0_row4).
              let val := addmod(
                /*column0_row3*/ mload(0x5a0),
                sub(
                  PRIME,
                  addmod(/*column0_row4*/ mload(0x5c0), /*column0_row4*/ mload(0x5c0), PRIME)),
                PRIME)
              mstore(0x1da0, val)
              }


              {
              // cpu/decode/flag_op1_base_op0_0 = 1 - (cpu__decode__opcode_range_check__bit_2 + cpu__decode__opcode_range_check__bit_4 + cpu__decode__opcode_range_check__bit_3).
              let val := addmod(
                1,
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_2*/ mload(0x1d60),
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_4*/ mload(0x1d80),
                      PRIME),
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_3*/ mload(0x1da0),
                    PRIME)),
                PRIME)
              mstore(0x1dc0, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_5 = column0_row5 - (column0_row6 + column0_row6).
              let val := addmod(
                /*column0_row5*/ mload(0x5e0),
                sub(
                  PRIME,
                  addmod(/*column0_row6*/ mload(0x600), /*column0_row6*/ mload(0x600), PRIME)),
                PRIME)
              mstore(0x1de0, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_6 = column0_row6 - (column0_row7 + column0_row7).
              let val := addmod(
                /*column0_row6*/ mload(0x600),
                sub(
                  PRIME,
                  addmod(/*column0_row7*/ mload(0x620), /*column0_row7*/ mload(0x620), PRIME)),
                PRIME)
              mstore(0x1e00, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_9 = column0_row9 - (column0_row10 + column0_row10).
              let val := addmod(
                /*column0_row9*/ mload(0x660),
                sub(
                  PRIME,
                  addmod(/*column0_row10*/ mload(0x680), /*column0_row10*/ mload(0x680), PRIME)),
                PRIME)
              mstore(0x1e20, val)
              }


              {
              // cpu/decode/flag_res_op1_0 = 1 - (cpu__decode__opcode_range_check__bit_5 + cpu__decode__opcode_range_check__bit_6 + cpu__decode__opcode_range_check__bit_9).
              let val := addmod(
                1,
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_5*/ mload(0x1de0),
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_6*/ mload(0x1e00),
                      PRIME),
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20),
                    PRIME)),
                PRIME)
              mstore(0x1e40, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_7 = column0_row7 - (column0_row8 + column0_row8).
              let val := addmod(
                /*column0_row7*/ mload(0x620),
                sub(
                  PRIME,
                  addmod(/*column0_row8*/ mload(0x640), /*column0_row8*/ mload(0x640), PRIME)),
                PRIME)
              mstore(0x1e60, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_8 = column0_row8 - (column0_row9 + column0_row9).
              let val := addmod(
                /*column0_row8*/ mload(0x640),
                sub(
                  PRIME,
                  addmod(/*column0_row9*/ mload(0x660), /*column0_row9*/ mload(0x660), PRIME)),
                PRIME)
              mstore(0x1e80, val)
              }


              {
              // cpu/decode/flag_pc_update_regular_0 = 1 - (cpu__decode__opcode_range_check__bit_7 + cpu__decode__opcode_range_check__bit_8 + cpu__decode__opcode_range_check__bit_9).
              let val := addmod(
                1,
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_7*/ mload(0x1e60),
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_8*/ mload(0x1e80),
                      PRIME),
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20),
                    PRIME)),
                PRIME)
              mstore(0x1ea0, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_12 = column0_row12 - (column0_row13 + column0_row13).
              let val := addmod(
                /*column0_row12*/ mload(0x6c0),
                sub(
                  PRIME,
                  addmod(/*column0_row13*/ mload(0x6e0), /*column0_row13*/ mload(0x6e0), PRIME)),
                PRIME)
              mstore(0x1ec0, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_13 = column0_row13 - (column0_row14 + column0_row14).
              let val := addmod(
                /*column0_row13*/ mload(0x6e0),
                sub(
                  PRIME,
                  addmod(/*column0_row14*/ mload(0x700), /*column0_row14*/ mload(0x700), PRIME)),
                PRIME)
              mstore(0x1ee0, val)
              }


              {
              // cpu/decode/fp_update_regular_0 = 1 - (cpu__decode__opcode_range_check__bit_12 + cpu__decode__opcode_range_check__bit_13).
              let val := addmod(
                1,
                sub(
                  PRIME,
                  addmod(
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_13*/ mload(0x1ee0),
                    PRIME)),
                PRIME)
              mstore(0x1f00, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_1 = column0_row1 - (column0_row2 + column0_row2).
              let val := addmod(
                /*column0_row1*/ mload(0x560),
                sub(
                  PRIME,
                  addmod(/*column0_row2*/ mload(0x580), /*column0_row2*/ mload(0x580), PRIME)),
                PRIME)
              mstore(0x1f20, val)
              }


              {
              // npc_reg_0 = column3_row0 + cpu__decode__opcode_range_check__bit_2 + 1.
              let val := addmod(
                addmod(
                  /*column3_row0*/ mload(0xb60),
                  /*intermediate_value/cpu/decode/opcode_range_check/bit_2*/ mload(0x1d60),
                  PRIME),
                1,
                PRIME)
              mstore(0x1f40, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_10 = column0_row10 - (column0_row11 + column0_row11).
              let val := addmod(
                /*column0_row10*/ mload(0x680),
                sub(
                  PRIME,
                  addmod(/*column0_row11*/ mload(0x6a0), /*column0_row11*/ mload(0x6a0), PRIME)),
                PRIME)
              mstore(0x1f60, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_11 = column0_row11 - (column0_row12 + column0_row12).
              let val := addmod(
                /*column0_row11*/ mload(0x6a0),
                sub(
                  PRIME,
                  addmod(/*column0_row12*/ mload(0x6c0), /*column0_row12*/ mload(0x6c0), PRIME)),
                PRIME)
              mstore(0x1f80, val)
              }


              {
              // cpu/decode/opcode_range_check/bit_14 = column0_row14 - (column0_row15 + column0_row15).
              let val := addmod(
                /*column0_row14*/ mload(0x700),
                sub(
                  PRIME,
                  addmod(/*column0_row15*/ mload(0x720), /*column0_row15*/ mload(0x720), PRIME)),
                PRIME)
              mstore(0x1fa0, val)
              }


              {
              // memory/address_diff_0 = column4_row2 - column4_row0.
              let val := addmod(/*column4_row2*/ mload(0x10e0), sub(PRIME, /*column4_row0*/ mload(0x10a0)), PRIME)
              mstore(0x1fc0, val)
              }


              {
              // range_check16/diff_0 = column6_row6 - column6_row2.
              let val := addmod(/*column6_row6*/ mload(0x1320), sub(PRIME, /*column6_row2*/ mload(0x12a0)), PRIME)
              mstore(0x1fe0, val)
              }


              {
              // pedersen/hash0/ec_subset_sum/bit_0 = column7_row0 - (column7_row4 + column7_row4).
              let val := addmod(
                /*column7_row0*/ mload(0x1520),
                sub(
                  PRIME,
                  addmod(/*column7_row4*/ mload(0x15a0), /*column7_row4*/ mload(0x15a0), PRIME)),
                PRIME)
              mstore(0x2000, val)
              }


              {
              // pedersen/hash0/ec_subset_sum/bit_neg_0 = 1 - pedersen__hash0__ec_subset_sum__bit_0.
              let val := addmod(
                1,
                sub(PRIME, /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000)),
                PRIME)
              mstore(0x2020, val)
              }


              {
              // range_check_builtin/value0_0 = column6_row12.
              let val := /*column6_row12*/ mload(0x1380)
              mstore(0x2040, val)
              }


              {
              // range_check_builtin/value1_0 = range_check_builtin__value0_0 * offset_size + column6_row28.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value0_0*/ mload(0x2040),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row28*/ mload(0x13a0),
                PRIME)
              mstore(0x2060, val)
              }


              {
              // range_check_builtin/value2_0 = range_check_builtin__value1_0 * offset_size + column6_row44.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value1_0*/ mload(0x2060),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row44*/ mload(0x13c0),
                PRIME)
              mstore(0x2080, val)
              }


              {
              // range_check_builtin/value3_0 = range_check_builtin__value2_0 * offset_size + column6_row60.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value2_0*/ mload(0x2080),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row60*/ mload(0x13e0),
                PRIME)
              mstore(0x20a0, val)
              }


              {
              // range_check_builtin/value4_0 = range_check_builtin__value3_0 * offset_size + column6_row76.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value3_0*/ mload(0x20a0),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row76*/ mload(0x1400),
                PRIME)
              mstore(0x20c0, val)
              }


              {
              // range_check_builtin/value5_0 = range_check_builtin__value4_0 * offset_size + column6_row92.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value4_0*/ mload(0x20c0),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row92*/ mload(0x1420),
                PRIME)
              mstore(0x20e0, val)
              }


              {
              // range_check_builtin/value6_0 = range_check_builtin__value5_0 * offset_size + column6_row108.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value5_0*/ mload(0x20e0),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row108*/ mload(0x1440),
                PRIME)
              mstore(0x2100, val)
              }


              {
              // range_check_builtin/value7_0 = range_check_builtin__value6_0 * offset_size + column6_row124.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check_builtin/value6_0*/ mload(0x2100),
                  /*offset_size*/ mload(0x100),
                  PRIME),
                /*column6_row124*/ mload(0x1460),
                PRIME)
              mstore(0x2120, val)
              }


              {
              // bitwise/sum_var_0_0 = column1_row0 + column1_row2 * 2 + column1_row4 * 4 + column1_row6 * 8 + column1_row8 * 18446744073709551616 + column1_row10 * 36893488147419103232 + column1_row12 * 73786976294838206464 + column1_row14 * 147573952589676412928.
              let val := addmod(
                addmod(
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            /*column1_row0*/ mload(0x740),
                            mulmod(/*column1_row2*/ mload(0x780), 2, PRIME),
                            PRIME),
                          mulmod(/*column1_row4*/ mload(0x7a0), 4, PRIME),
                          PRIME),
                        mulmod(/*column1_row6*/ mload(0x7c0), 8, PRIME),
                        PRIME),
                      mulmod(/*column1_row8*/ mload(0x7e0), 18446744073709551616, PRIME),
                      PRIME),
                    mulmod(/*column1_row10*/ mload(0x800), 36893488147419103232, PRIME),
                    PRIME),
                  mulmod(/*column1_row12*/ mload(0x820), 73786976294838206464, PRIME),
                  PRIME),
                mulmod(/*column1_row14*/ mload(0x840), 147573952589676412928, PRIME),
                PRIME)
              mstore(0x2140, val)
              }


              {
              // bitwise/sum_var_8_0 = column1_row16 * 340282366920938463463374607431768211456 + column1_row18 * 680564733841876926926749214863536422912 + column1_row20 * 1361129467683753853853498429727072845824 + column1_row22 * 2722258935367507707706996859454145691648 + column1_row24 * 6277101735386680763835789423207666416102355444464034512896 + column1_row26 * 12554203470773361527671578846415332832204710888928069025792 + column1_row28 * 25108406941546723055343157692830665664409421777856138051584 + column1_row30 * 50216813883093446110686315385661331328818843555712276103168.
              let val := addmod(
                addmod(
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            mulmod(/*column1_row16*/ mload(0x860), 340282366920938463463374607431768211456, PRIME),
                            mulmod(/*column1_row18*/ mload(0x880), 680564733841876926926749214863536422912, PRIME),
                            PRIME),
                          mulmod(/*column1_row20*/ mload(0x8a0), 1361129467683753853853498429727072845824, PRIME),
                          PRIME),
                        mulmod(/*column1_row22*/ mload(0x8c0), 2722258935367507707706996859454145691648, PRIME),
                        PRIME),
                      mulmod(
                        /*column1_row24*/ mload(0x8e0),
                        6277101735386680763835789423207666416102355444464034512896,
                        PRIME),
                      PRIME),
                    mulmod(
                      /*column1_row26*/ mload(0x900),
                      12554203470773361527671578846415332832204710888928069025792,
                      PRIME),
                    PRIME),
                  mulmod(
                    /*column1_row28*/ mload(0x920),
                    25108406941546723055343157692830665664409421777856138051584,
                    PRIME),
                  PRIME),
                mulmod(
                  /*column1_row30*/ mload(0x940),
                  50216813883093446110686315385661331328818843555712276103168,
                  PRIME),
                PRIME)
              mstore(0x2160, val)
              }


              {
              // poseidon/poseidon/full_rounds_state0_cubed_0 = column8_row6 * column8_row9.
              let val := mulmod(/*column8_row6*/ mload(0x18e0), /*column8_row9*/ mload(0x1920), PRIME)
              mstore(0x2180, val)
              }


              {
              // poseidon/poseidon/full_rounds_state1_cubed_0 = column8_row14 * column8_row5.
              let val := mulmod(/*column8_row14*/ mload(0x19a0), /*column8_row5*/ mload(0x18c0), PRIME)
              mstore(0x21a0, val)
              }


              {
              // poseidon/poseidon/full_rounds_state2_cubed_0 = column8_row1 * column8_row13.
              let val := mulmod(/*column8_row1*/ mload(0x1860), /*column8_row13*/ mload(0x1980), PRIME)
              mstore(0x21c0, val)
              }


              {
              // poseidon/poseidon/full_rounds_state0_cubed_7 = column8_row118 * column8_row121.
              let val := mulmod(/*column8_row118*/ mload(0x1bc0), /*column8_row121*/ mload(0x1be0), PRIME)
              mstore(0x21e0, val)
              }


              {
              // poseidon/poseidon/full_rounds_state1_cubed_7 = column8_row126 * column8_row117.
              let val := mulmod(/*column8_row126*/ mload(0x1c20), /*column8_row117*/ mload(0x1ba0), PRIME)
              mstore(0x2200, val)
              }


              {
              // poseidon/poseidon/full_rounds_state2_cubed_7 = column8_row113 * column8_row125.
              let val := mulmod(/*column8_row113*/ mload(0x1b80), /*column8_row125*/ mload(0x1c00), PRIME)
              mstore(0x2220, val)
              }


              {
              // poseidon/poseidon/full_rounds_state0_cubed_3 = column8_row54 * column8_row57.
              let val := mulmod(/*column8_row54*/ mload(0x1aa0), /*column8_row57*/ mload(0x1ac0), PRIME)
              mstore(0x2240, val)
              }


              {
              // poseidon/poseidon/full_rounds_state1_cubed_3 = column8_row62 * column8_row53.
              let val := mulmod(/*column8_row62*/ mload(0x1b00), /*column8_row53*/ mload(0x1a80), PRIME)
              mstore(0x2260, val)
              }


              {
              // poseidon/poseidon/full_rounds_state2_cubed_3 = column8_row49 * column8_row61.
              let val := mulmod(/*column8_row49*/ mload(0x1a60), /*column8_row61*/ mload(0x1ae0), PRIME)
              mstore(0x2280, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state0_cubed_0 = column5_row0 * column5_row1.
              let val := mulmod(/*column5_row0*/ mload(0x1120), /*column5_row1*/ mload(0x1140), PRIME)
              mstore(0x22a0, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state0_cubed_1 = column5_row2 * column5_row3.
              let val := mulmod(/*column5_row2*/ mload(0x1160), /*column5_row3*/ mload(0x1180), PRIME)
              mstore(0x22c0, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state0_cubed_2 = column5_row4 * column5_row5.
              let val := mulmod(/*column5_row4*/ mload(0x11a0), /*column5_row5*/ mload(0x11c0), PRIME)
              mstore(0x22e0, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_0 = column7_row1 * column7_row3.
              let val := mulmod(/*column7_row1*/ mload(0x1540), /*column7_row3*/ mload(0x1580), PRIME)
              mstore(0x2300, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_1 = column7_row5 * column7_row7.
              let val := mulmod(/*column7_row5*/ mload(0x15c0), /*column7_row7*/ mload(0x15e0), PRIME)
              mstore(0x2320, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_2 = column7_row9 * column7_row11.
              let val := mulmod(/*column7_row9*/ mload(0x1600), /*column7_row11*/ mload(0x1620), PRIME)
              mstore(0x2340, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_19 = column7_row77 * column7_row79.
              let val := mulmod(/*column7_row77*/ mload(0x1660), /*column7_row79*/ mload(0x1680), PRIME)
              mstore(0x2360, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_20 = column7_row81 * column7_row83.
              let val := mulmod(/*column7_row81*/ mload(0x16a0), /*column7_row83*/ mload(0x16c0), PRIME)
              mstore(0x2380, val)
              }


              {
              // poseidon/poseidon/partial_rounds_state1_cubed_21 = column7_row85 * column7_row87.
              let val := mulmod(/*column7_row85*/ mload(0x16e0), /*column7_row87*/ mload(0x1700), PRIME)
              mstore(0x23a0, val)
              }


              let composition_alpha_pow := 1
              let composition_alpha := /*composition_alpha*/ mload(0x520)
              {
              // Constraint expression for cpu/decode/opcode_range_check/bit: cpu__decode__opcode_range_check__bit_0 * cpu__decode__opcode_range_check__bit_0 - cpu__decode__opcode_range_check__bit_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40),
                  /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40),
                  PRIME),
                sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40)),
                PRIME)

              // Numerator: point^(trace_length / 16) - trace_generator^(15 * trace_length / 16).
              // val *= domains[3].
              val := mulmod(val, /*domains[3]*/ mload(0x2a20), PRIME)
              // Denominator: point^trace_length - 1.
              // val *= denominator_invs[0].
              val := mulmod(val, /*denominator_invs[0]*/ mload(0x2d40), PRIME)

              // res += val * alpha ** 0.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/opcode_range_check/zero: column0_row0.
              let val := /*column0_row0*/ mload(0x540)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - trace_generator^(15 * trace_length / 16).
              // val *= denominator_invs[1].
              val := mulmod(val, /*denominator_invs[1]*/ mload(0x2d60), PRIME)

              // res += val * alpha ** 1.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/opcode_range_check_input: column3_row1 - (((column0_row0 * offset_size + column6_row4) * offset_size + column6_row8) * offset_size + column6_row0).
              let val := addmod(
                /*column3_row1*/ mload(0xb80),
                sub(
                  PRIME,
                  addmod(
                    mulmod(
                      addmod(
                        mulmod(
                          addmod(
                            mulmod(/*column0_row0*/ mload(0x540), /*offset_size*/ mload(0x100), PRIME),
                            /*column6_row4*/ mload(0x12e0),
                            PRIME),
                          /*offset_size*/ mload(0x100),
                          PRIME),
                        /*column6_row8*/ mload(0x1360),
                        PRIME),
                      /*offset_size*/ mload(0x100),
                      PRIME),
                    /*column6_row0*/ mload(0x1260),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 2.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/flag_op1_base_op0_bit: cpu__decode__flag_op1_base_op0_0 * cpu__decode__flag_op1_base_op0_0 - cpu__decode__flag_op1_base_op0_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/cpu/decode/flag_op1_base_op0_0*/ mload(0x1dc0),
                  /*intermediate_value/cpu/decode/flag_op1_base_op0_0*/ mload(0x1dc0),
                  PRIME),
                sub(PRIME, /*intermediate_value/cpu/decode/flag_op1_base_op0_0*/ mload(0x1dc0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 3.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/flag_res_op1_bit: cpu__decode__flag_res_op1_0 * cpu__decode__flag_res_op1_0 - cpu__decode__flag_res_op1_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/cpu/decode/flag_res_op1_0*/ mload(0x1e40),
                  /*intermediate_value/cpu/decode/flag_res_op1_0*/ mload(0x1e40),
                  PRIME),
                sub(PRIME, /*intermediate_value/cpu/decode/flag_res_op1_0*/ mload(0x1e40)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 4.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/flag_pc_update_regular_bit: cpu__decode__flag_pc_update_regular_0 * cpu__decode__flag_pc_update_regular_0 - cpu__decode__flag_pc_update_regular_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/cpu/decode/flag_pc_update_regular_0*/ mload(0x1ea0),
                  /*intermediate_value/cpu/decode/flag_pc_update_regular_0*/ mload(0x1ea0),
                  PRIME),
                sub(PRIME, /*intermediate_value/cpu/decode/flag_pc_update_regular_0*/ mload(0x1ea0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 5.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/decode/fp_update_regular_bit: cpu__decode__fp_update_regular_0 * cpu__decode__fp_update_regular_0 - cpu__decode__fp_update_regular_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/cpu/decode/fp_update_regular_0*/ mload(0x1f00),
                  /*intermediate_value/cpu/decode/fp_update_regular_0*/ mload(0x1f00),
                  PRIME),
                sub(PRIME, /*intermediate_value/cpu/decode/fp_update_regular_0*/ mload(0x1f00)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 6.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/operands/mem_dst_addr: column3_row8 + half_offset_size - (cpu__decode__opcode_range_check__bit_0 * column8_row8 + (1 - cpu__decode__opcode_range_check__bit_0) * column8_row0 + column6_row0).
              let val := addmod(
                addmod(/*column3_row8*/ mload(0xc60), /*half_offset_size*/ mload(0x120), PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40),
                        /*column8_row8*/ mload(0x1900),
                        PRIME),
                      mulmod(
                        addmod(
                          1,
                          sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40)),
                          PRIME),
                        /*column8_row0*/ mload(0x1840),
                        PRIME),
                      PRIME),
                    /*column6_row0*/ mload(0x1260),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 7.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/operands/mem0_addr: column3_row4 + half_offset_size - (cpu__decode__opcode_range_check__bit_1 * column8_row8 + (1 - cpu__decode__opcode_range_check__bit_1) * column8_row0 + column6_row8).
              let val := addmod(
                addmod(/*column3_row4*/ mload(0xbe0), /*half_offset_size*/ mload(0x120), PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_1*/ mload(0x1f20),
                        /*column8_row8*/ mload(0x1900),
                        PRIME),
                      mulmod(
                        addmod(
                          1,
                          sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_1*/ mload(0x1f20)),
                          PRIME),
                        /*column8_row0*/ mload(0x1840),
                        PRIME),
                      PRIME),
                    /*column6_row8*/ mload(0x1360),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 8.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/operands/mem1_addr: column3_row12 + half_offset_size - (cpu__decode__opcode_range_check__bit_2 * column3_row0 + cpu__decode__opcode_range_check__bit_4 * column8_row0 + cpu__decode__opcode_range_check__bit_3 * column8_row8 + cpu__decode__flag_op1_base_op0_0 * column3_row5 + column6_row4).
              let val := addmod(
                addmod(/*column3_row12*/ mload(0xce0), /*half_offset_size*/ mload(0x120), PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          mulmod(
                            /*intermediate_value/cpu/decode/opcode_range_check/bit_2*/ mload(0x1d60),
                            /*column3_row0*/ mload(0xb60),
                            PRIME),
                          mulmod(
                            /*intermediate_value/cpu/decode/opcode_range_check/bit_4*/ mload(0x1d80),
                            /*column8_row0*/ mload(0x1840),
                            PRIME),
                          PRIME),
                        mulmod(
                          /*intermediate_value/cpu/decode/opcode_range_check/bit_3*/ mload(0x1da0),
                          /*column8_row8*/ mload(0x1900),
                          PRIME),
                        PRIME),
                      mulmod(
                        /*intermediate_value/cpu/decode/flag_op1_base_op0_0*/ mload(0x1dc0),
                        /*column3_row5*/ mload(0xc00),
                        PRIME),
                      PRIME),
                    /*column6_row4*/ mload(0x12e0),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 9.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/operands/ops_mul: column8_row4 - column3_row5 * column3_row13.
              let val := addmod(
                /*column8_row4*/ mload(0x18a0),
                sub(
                  PRIME,
                  mulmod(/*column3_row5*/ mload(0xc00), /*column3_row13*/ mload(0xd00), PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 10.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/operands/res: (1 - cpu__decode__opcode_range_check__bit_9) * column8_row12 - (cpu__decode__opcode_range_check__bit_5 * (column3_row5 + column3_row13) + cpu__decode__opcode_range_check__bit_6 * column8_row4 + cpu__decode__flag_res_op1_0 * column3_row13).
              let val := addmod(
                mulmod(
                  addmod(
                    1,
                    sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20)),
                    PRIME),
                  /*column8_row12*/ mload(0x1960),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_5*/ mload(0x1de0),
                        addmod(/*column3_row5*/ mload(0xc00), /*column3_row13*/ mload(0xd00), PRIME),
                        PRIME),
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_6*/ mload(0x1e00),
                        /*column8_row4*/ mload(0x18a0),
                        PRIME),
                      PRIME),
                    mulmod(
                      /*intermediate_value/cpu/decode/flag_res_op1_0*/ mload(0x1e40),
                      /*column3_row13*/ mload(0xd00),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 11.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_pc/tmp0: column8_row2 - cpu__decode__opcode_range_check__bit_9 * column3_row9.
              let val := addmod(
                /*column8_row2*/ mload(0x1880),
                sub(
                  PRIME,
                  mulmod(
                    /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20),
                    /*column3_row9*/ mload(0xc80),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 12.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_pc/tmp1: column8_row10 - column8_row2 * column8_row12.
              let val := addmod(
                /*column8_row10*/ mload(0x1940),
                sub(
                  PRIME,
                  mulmod(/*column8_row2*/ mload(0x1880), /*column8_row12*/ mload(0x1960), PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 13.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_pc/pc_cond_negative: (1 - cpu__decode__opcode_range_check__bit_9) * column3_row16 + column8_row2 * (column3_row16 - (column3_row0 + column3_row13)) - (cpu__decode__flag_pc_update_regular_0 * npc_reg_0 + cpu__decode__opcode_range_check__bit_7 * column8_row12 + cpu__decode__opcode_range_check__bit_8 * (column3_row0 + column8_row12)).
              let val := addmod(
                addmod(
                  mulmod(
                    addmod(
                      1,
                      sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20)),
                      PRIME),
                    /*column3_row16*/ mload(0xd20),
                    PRIME),
                  mulmod(
                    /*column8_row2*/ mload(0x1880),
                    addmod(
                      /*column3_row16*/ mload(0xd20),
                      sub(
                        PRIME,
                        addmod(/*column3_row0*/ mload(0xb60), /*column3_row13*/ mload(0xd00), PRIME)),
                      PRIME),
                    PRIME),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      mulmod(
                        /*intermediate_value/cpu/decode/flag_pc_update_regular_0*/ mload(0x1ea0),
                        /*intermediate_value/npc_reg_0*/ mload(0x1f40),
                        PRIME),
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_7*/ mload(0x1e60),
                        /*column8_row12*/ mload(0x1960),
                        PRIME),
                      PRIME),
                    mulmod(
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_8*/ mload(0x1e80),
                      addmod(/*column3_row0*/ mload(0xb60), /*column8_row12*/ mload(0x1960), PRIME),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 14.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_pc/pc_cond_positive: (column8_row10 - cpu__decode__opcode_range_check__bit_9) * (column3_row16 - npc_reg_0).
              let val := mulmod(
                addmod(
                  /*column8_row10*/ mload(0x1940),
                  sub(PRIME, /*intermediate_value/cpu/decode/opcode_range_check/bit_9*/ mload(0x1e20)),
                  PRIME),
                addmod(
                  /*column3_row16*/ mload(0xd20),
                  sub(PRIME, /*intermediate_value/npc_reg_0*/ mload(0x1f40)),
                  PRIME),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 15.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_ap/ap_update: column8_row16 - (column8_row0 + cpu__decode__opcode_range_check__bit_10 * column8_row12 + cpu__decode__opcode_range_check__bit_11 + cpu__decode__opcode_range_check__bit_12 * 2).
              let val := addmod(
                /*column8_row16*/ mload(0x19c0),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        /*column8_row0*/ mload(0x1840),
                        mulmod(
                          /*intermediate_value/cpu/decode/opcode_range_check/bit_10*/ mload(0x1f60),
                          /*column8_row12*/ mload(0x1960),
                          PRIME),
                        PRIME),
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_11*/ mload(0x1f80),
                      PRIME),
                    mulmod(/*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0), 2, PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 16.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/update_registers/update_fp/fp_update: column8_row24 - (cpu__decode__fp_update_regular_0 * column8_row8 + cpu__decode__opcode_range_check__bit_13 * column3_row9 + cpu__decode__opcode_range_check__bit_12 * (column8_row0 + 2)).
              let val := addmod(
                /*column8_row24*/ mload(0x1a20),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      mulmod(
                        /*intermediate_value/cpu/decode/fp_update_regular_0*/ mload(0x1f00),
                        /*column8_row8*/ mload(0x1900),
                        PRIME),
                      mulmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_13*/ mload(0x1ee0),
                        /*column3_row9*/ mload(0xc80),
                        PRIME),
                      PRIME),
                    mulmod(
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                      addmod(/*column8_row0*/ mload(0x1840), 2, PRIME),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 16).
              // val *= domains[20].
              val := mulmod(val, /*domains[20]*/ mload(0x2c40), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 17.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/call/push_fp: cpu__decode__opcode_range_check__bit_12 * (column3_row9 - column8_row8).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                addmod(/*column3_row9*/ mload(0xc80), sub(PRIME, /*column8_row8*/ mload(0x1900)), PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 18.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/call/push_pc: cpu__decode__opcode_range_check__bit_12 * (column3_row5 - (column3_row0 + cpu__decode__opcode_range_check__bit_2 + 1)).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                addmod(
                  /*column3_row5*/ mload(0xc00),
                  sub(
                    PRIME,
                    addmod(
                      addmod(
                        /*column3_row0*/ mload(0xb60),
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_2*/ mload(0x1d60),
                        PRIME),
                      1,
                      PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 19.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/call/off0: cpu__decode__opcode_range_check__bit_12 * (column6_row0 - half_offset_size).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                addmod(
                  /*column6_row0*/ mload(0x1260),
                  sub(PRIME, /*half_offset_size*/ mload(0x120)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 20.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/call/off1: cpu__decode__opcode_range_check__bit_12 * (column6_row8 - (half_offset_size + 1)).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                addmod(
                  /*column6_row8*/ mload(0x1360),
                  sub(PRIME, addmod(/*half_offset_size*/ mload(0x120), 1, PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 21.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/call/flags: cpu__decode__opcode_range_check__bit_12 * (cpu__decode__opcode_range_check__bit_12 + cpu__decode__opcode_range_check__bit_12 + 1 + 1 - (cpu__decode__opcode_range_check__bit_0 + cpu__decode__opcode_range_check__bit_1 + 4)).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                addmod(
                  addmod(
                    addmod(
                      addmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_12*/ mload(0x1ec0),
                        PRIME),
                      1,
                      PRIME),
                    1,
                    PRIME),
                  sub(
                    PRIME,
                    addmod(
                      addmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40),
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_1*/ mload(0x1f20),
                        PRIME),
                      4,
                      PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 22.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/ret/off0: cpu__decode__opcode_range_check__bit_13 * (column6_row0 + 2 - half_offset_size).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_13*/ mload(0x1ee0),
                addmod(
                  addmod(/*column6_row0*/ mload(0x1260), 2, PRIME),
                  sub(PRIME, /*half_offset_size*/ mload(0x120)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 23.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/ret/off2: cpu__decode__opcode_range_check__bit_13 * (column6_row4 + 1 - half_offset_size).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_13*/ mload(0x1ee0),
                addmod(
                  addmod(/*column6_row4*/ mload(0x12e0), 1, PRIME),
                  sub(PRIME, /*half_offset_size*/ mload(0x120)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 24.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/ret/flags: cpu__decode__opcode_range_check__bit_13 * (cpu__decode__opcode_range_check__bit_7 + cpu__decode__opcode_range_check__bit_0 + cpu__decode__opcode_range_check__bit_3 + cpu__decode__flag_res_op1_0 - 4).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_13*/ mload(0x1ee0),
                addmod(
                  addmod(
                    addmod(
                      addmod(
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_7*/ mload(0x1e60),
                        /*intermediate_value/cpu/decode/opcode_range_check/bit_0*/ mload(0x1d40),
                        PRIME),
                      /*intermediate_value/cpu/decode/opcode_range_check/bit_3*/ mload(0x1da0),
                      PRIME),
                    /*intermediate_value/cpu/decode/flag_res_op1_0*/ mload(0x1e40),
                    PRIME),
                  sub(PRIME, 4),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 25.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for cpu/opcodes/assert_eq/assert_eq: cpu__decode__opcode_range_check__bit_14 * (column3_row9 - column8_row12).
              let val := mulmod(
                /*intermediate_value/cpu/decode/opcode_range_check/bit_14*/ mload(0x1fa0),
                addmod(/*column3_row9*/ mload(0xc80), sub(PRIME, /*column8_row12*/ mload(0x1960)), PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 26.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for initial_ap: column8_row0 - initial_ap.
              let val := addmod(/*column8_row0*/ mload(0x1840), sub(PRIME, /*initial_ap*/ mload(0x140)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 27.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for initial_fp: column8_row8 - initial_ap.
              let val := addmod(/*column8_row8*/ mload(0x1900), sub(PRIME, /*initial_ap*/ mload(0x140)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 28.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for initial_pc: column3_row0 - initial_pc.
              let val := addmod(/*column3_row0*/ mload(0xb60), sub(PRIME, /*initial_pc*/ mload(0x160)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 29.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for final_ap: column8_row0 - final_ap.
              let val := addmod(/*column8_row0*/ mload(0x1840), sub(PRIME, /*final_ap*/ mload(0x180)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 16).
              // val *= denominator_invs[3].
              val := mulmod(val, /*denominator_invs[3]*/ mload(0x2da0), PRIME)

              // res += val * alpha ** 30.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for final_fp: column8_row8 - initial_ap.
              let val := addmod(/*column8_row8*/ mload(0x1900), sub(PRIME, /*initial_ap*/ mload(0x140)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 16).
              // val *= denominator_invs[3].
              val := mulmod(val, /*denominator_invs[3]*/ mload(0x2da0), PRIME)

              // res += val * alpha ** 31.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for final_pc: column3_row0 - final_pc.
              let val := addmod(/*column3_row0*/ mload(0xb60), sub(PRIME, /*final_pc*/ mload(0x1a0)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 16).
              // val *= denominator_invs[3].
              val := mulmod(val, /*denominator_invs[3]*/ mload(0x2da0), PRIME)

              // res += val * alpha ** 32.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/multi_column_perm/perm/init0: (memory/multi_column_perm/perm/interaction_elm - (column4_row0 + memory/multi_column_perm/hash_interaction_elm0 * column4_row1)) * column11_inter1_row0 + column3_row0 + memory/multi_column_perm/hash_interaction_elm0 * column3_row1 - memory/multi_column_perm/perm/interaction_elm.
              let val := addmod(
                addmod(
                  addmod(
                    mulmod(
                      addmod(
                        /*memory/multi_column_perm/perm/interaction_elm*/ mload(0x1c0),
                        sub(
                          PRIME,
                          addmod(
                            /*column4_row0*/ mload(0x10a0),
                            mulmod(
                              /*memory/multi_column_perm/hash_interaction_elm0*/ mload(0x1e0),
                              /*column4_row1*/ mload(0x10c0),
                              PRIME),
                            PRIME)),
                        PRIME),
                      /*column11_inter1_row0*/ mload(0x1cc0),
                      PRIME),
                    /*column3_row0*/ mload(0xb60),
                    PRIME),
                  mulmod(
                    /*memory/multi_column_perm/hash_interaction_elm0*/ mload(0x1e0),
                    /*column3_row1*/ mload(0xb80),
                    PRIME),
                  PRIME),
                sub(PRIME, /*memory/multi_column_perm/perm/interaction_elm*/ mload(0x1c0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 33.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/multi_column_perm/perm/step0: (memory/multi_column_perm/perm/interaction_elm - (column4_row2 + memory/multi_column_perm/hash_interaction_elm0 * column4_row3)) * column11_inter1_row2 - (memory/multi_column_perm/perm/interaction_elm - (column3_row2 + memory/multi_column_perm/hash_interaction_elm0 * column3_row3)) * column11_inter1_row0.
              let val := addmod(
                mulmod(
                  addmod(
                    /*memory/multi_column_perm/perm/interaction_elm*/ mload(0x1c0),
                    sub(
                      PRIME,
                      addmod(
                        /*column4_row2*/ mload(0x10e0),
                        mulmod(
                          /*memory/multi_column_perm/hash_interaction_elm0*/ mload(0x1e0),
                          /*column4_row3*/ mload(0x1100),
                          PRIME),
                        PRIME)),
                    PRIME),
                  /*column11_inter1_row2*/ mload(0x1d00),
                  PRIME),
                sub(
                  PRIME,
                  mulmod(
                    addmod(
                      /*memory/multi_column_perm/perm/interaction_elm*/ mload(0x1c0),
                      sub(
                        PRIME,
                        addmod(
                          /*column3_row2*/ mload(0xba0),
                          mulmod(
                            /*memory/multi_column_perm/hash_interaction_elm0*/ mload(0x1e0),
                            /*column3_row3*/ mload(0xbc0),
                            PRIME),
                          PRIME)),
                      PRIME),
                    /*column11_inter1_row0*/ mload(0x1cc0),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 2).
              // val *= domains[22].
              val := mulmod(val, /*domains[22]*/ mload(0x2c80), PRIME)
              // Denominator: point^(trace_length / 2) - 1.
              // val *= denominator_invs[5].
              val := mulmod(val, /*denominator_invs[5]*/ mload(0x2de0), PRIME)

              // res += val * alpha ** 34.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/multi_column_perm/perm/last: column11_inter1_row0 - memory/multi_column_perm/perm/public_memory_prod.
              let val := addmod(
                /*column11_inter1_row0*/ mload(0x1cc0),
                sub(PRIME, /*memory/multi_column_perm/perm/public_memory_prod*/ mload(0x200)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 2).
              // val *= denominator_invs[6].
              val := mulmod(val, /*denominator_invs[6]*/ mload(0x2e00), PRIME)

              // res += val * alpha ** 35.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/diff_is_bit: memory__address_diff_0 * memory__address_diff_0 - memory__address_diff_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/memory/address_diff_0*/ mload(0x1fc0),
                  /*intermediate_value/memory/address_diff_0*/ mload(0x1fc0),
                  PRIME),
                sub(PRIME, /*intermediate_value/memory/address_diff_0*/ mload(0x1fc0)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 2).
              // val *= domains[22].
              val := mulmod(val, /*domains[22]*/ mload(0x2c80), PRIME)
              // Denominator: point^(trace_length / 2) - 1.
              // val *= denominator_invs[5].
              val := mulmod(val, /*denominator_invs[5]*/ mload(0x2de0), PRIME)

              // res += val * alpha ** 36.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/is_func: (memory__address_diff_0 - 1) * (column4_row1 - column4_row3).
              let val := mulmod(
                addmod(/*intermediate_value/memory/address_diff_0*/ mload(0x1fc0), sub(PRIME, 1), PRIME),
                addmod(/*column4_row1*/ mload(0x10c0), sub(PRIME, /*column4_row3*/ mload(0x1100)), PRIME),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 2).
              // val *= domains[22].
              val := mulmod(val, /*domains[22]*/ mload(0x2c80), PRIME)
              // Denominator: point^(trace_length / 2) - 1.
              // val *= denominator_invs[5].
              val := mulmod(val, /*denominator_invs[5]*/ mload(0x2de0), PRIME)

              // res += val * alpha ** 37.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for memory/initial_addr: column4_row0 - 1.
              let val := addmod(/*column4_row0*/ mload(0x10a0), sub(PRIME, 1), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 38.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for public_memory_addr_zero: column3_row2.
              let val := /*column3_row2*/ mload(0xba0)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 39.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for public_memory_value_zero: column3_row3.
              let val := /*column3_row3*/ mload(0xbc0)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 40.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/perm/init0: (range_check16/perm/interaction_elm - column6_row2) * column11_inter1_row1 + column6_row0 - range_check16/perm/interaction_elm.
              let val := addmod(
                addmod(
                  mulmod(
                    addmod(
                      /*range_check16/perm/interaction_elm*/ mload(0x220),
                      sub(PRIME, /*column6_row2*/ mload(0x12a0)),
                      PRIME),
                    /*column11_inter1_row1*/ mload(0x1ce0),
                    PRIME),
                  /*column6_row0*/ mload(0x1260),
                  PRIME),
                sub(PRIME, /*range_check16/perm/interaction_elm*/ mload(0x220)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 41.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/perm/step0: (range_check16/perm/interaction_elm - column6_row6) * column11_inter1_row5 - (range_check16/perm/interaction_elm - column6_row4) * column11_inter1_row1.
              let val := addmod(
                mulmod(
                  addmod(
                    /*range_check16/perm/interaction_elm*/ mload(0x220),
                    sub(PRIME, /*column6_row6*/ mload(0x1320)),
                    PRIME),
                  /*column11_inter1_row5*/ mload(0x1d20),
                  PRIME),
                sub(
                  PRIME,
                  mulmod(
                    addmod(
                      /*range_check16/perm/interaction_elm*/ mload(0x220),
                      sub(PRIME, /*column6_row4*/ mload(0x12e0)),
                      PRIME),
                    /*column11_inter1_row1*/ mload(0x1ce0),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 4).
              // val *= domains[23].
              val := mulmod(val, /*domains[23]*/ mload(0x2ca0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 42.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/perm/last: column11_inter1_row1 - range_check16/perm/public_memory_prod.
              let val := addmod(
                /*column11_inter1_row1*/ mload(0x1ce0),
                sub(PRIME, /*range_check16/perm/public_memory_prod*/ mload(0x240)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 4).
              // val *= denominator_invs[8].
              val := mulmod(val, /*denominator_invs[8]*/ mload(0x2e40), PRIME)

              // res += val * alpha ** 43.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/diff_is_bit: range_check16__diff_0 * range_check16__diff_0 - range_check16__diff_0.
              let val := addmod(
                mulmod(
                  /*intermediate_value/range_check16/diff_0*/ mload(0x1fe0),
                  /*intermediate_value/range_check16/diff_0*/ mload(0x1fe0),
                  PRIME),
                sub(PRIME, /*intermediate_value/range_check16/diff_0*/ mload(0x1fe0)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 4).
              // val *= domains[23].
              val := mulmod(val, /*domains[23]*/ mload(0x2ca0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 44.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/minimum: column6_row2 - range_check_min.
              let val := addmod(/*column6_row2*/ mload(0x12a0), sub(PRIME, /*range_check_min*/ mload(0x260)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 45.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check16/maximum: column6_row2 - range_check_max.
              let val := addmod(/*column6_row2*/ mload(0x12a0), sub(PRIME, /*range_check_max*/ mload(0x280)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 4).
              // val *= denominator_invs[8].
              val := mulmod(val, /*denominator_invs[8]*/ mload(0x2e40), PRIME)

              // res += val * alpha ** 46.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/permutation/init0: (diluted_check/permutation/interaction_elm - column2_row0) * column10_inter1_row0 + column1_row0 - diluted_check/permutation/interaction_elm.
              let val := addmod(
                addmod(
                  mulmod(
                    addmod(
                      /*diluted_check/permutation/interaction_elm*/ mload(0x2a0),
                      sub(PRIME, /*column2_row0*/ mload(0xb20)),
                      PRIME),
                    /*column10_inter1_row0*/ mload(0x1c80),
                    PRIME),
                  /*column1_row0*/ mload(0x740),
                  PRIME),
                sub(PRIME, /*diluted_check/permutation/interaction_elm*/ mload(0x2a0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 47.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/permutation/step0: (diluted_check/permutation/interaction_elm - column2_row1) * column10_inter1_row1 - (diluted_check/permutation/interaction_elm - column1_row1) * column10_inter1_row0.
              let val := addmod(
                mulmod(
                  addmod(
                    /*diluted_check/permutation/interaction_elm*/ mload(0x2a0),
                    sub(PRIME, /*column2_row1*/ mload(0xb40)),
                    PRIME),
                  /*column10_inter1_row1*/ mload(0x1ca0),
                  PRIME),
                sub(
                  PRIME,
                  mulmod(
                    addmod(
                      /*diluted_check/permutation/interaction_elm*/ mload(0x2a0),
                      sub(PRIME, /*column1_row1*/ mload(0x760)),
                      PRIME),
                    /*column10_inter1_row0*/ mload(0x1c80),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 1).
              // val *= domains[24].
              val := mulmod(val, /*domains[24]*/ mload(0x2cc0), PRIME)
              // Denominator: point^trace_length - 1.
              // val *= denominator_invs[0].
              val := mulmod(val, /*denominator_invs[0]*/ mload(0x2d40), PRIME)

              // res += val * alpha ** 48.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/permutation/last: column10_inter1_row0 - diluted_check/permutation/public_memory_prod.
              let val := addmod(
                /*column10_inter1_row0*/ mload(0x1c80),
                sub(PRIME, /*diluted_check/permutation/public_memory_prod*/ mload(0x2c0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 1).
              // val *= denominator_invs[9].
              val := mulmod(val, /*denominator_invs[9]*/ mload(0x2e60), PRIME)

              // res += val * alpha ** 49.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/init: column9_inter1_row0 - 1.
              let val := addmod(/*column9_inter1_row0*/ mload(0x1c40), sub(PRIME, 1), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 50.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/first_element: column2_row0 - diluted_check/first_elm.
              let val := addmod(
                /*column2_row0*/ mload(0xb20),
                sub(PRIME, /*diluted_check/first_elm*/ mload(0x2e0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 51.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/step: column9_inter1_row1 - (column9_inter1_row0 * (1 + diluted_check/interaction_z * (column2_row1 - column2_row0)) + diluted_check/interaction_alpha * (column2_row1 - column2_row0) * (column2_row1 - column2_row0)).
              let val := addmod(
                /*column9_inter1_row1*/ mload(0x1c60),
                sub(
                  PRIME,
                  addmod(
                    mulmod(
                      /*column9_inter1_row0*/ mload(0x1c40),
                      addmod(
                        1,
                        mulmod(
                          /*diluted_check/interaction_z*/ mload(0x300),
                          addmod(/*column2_row1*/ mload(0xb40), sub(PRIME, /*column2_row0*/ mload(0xb20)), PRIME),
                          PRIME),
                        PRIME),
                      PRIME),
                    mulmod(
                      mulmod(
                        /*diluted_check/interaction_alpha*/ mload(0x320),
                        addmod(/*column2_row1*/ mload(0xb40), sub(PRIME, /*column2_row0*/ mload(0xb20)), PRIME),
                        PRIME),
                      addmod(/*column2_row1*/ mload(0xb40), sub(PRIME, /*column2_row0*/ mload(0xb20)), PRIME),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 1).
              // val *= domains[24].
              val := mulmod(val, /*domains[24]*/ mload(0x2cc0), PRIME)
              // Denominator: point^trace_length - 1.
              // val *= denominator_invs[0].
              val := mulmod(val, /*denominator_invs[0]*/ mload(0x2d40), PRIME)

              // res += val * alpha ** 52.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for diluted_check/last: column9_inter1_row0 - diluted_check/final_cum_val.
              let val := addmod(
                /*column9_inter1_row0*/ mload(0x1c40),
                sub(PRIME, /*diluted_check/final_cum_val*/ mload(0x340)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - trace_generator^(trace_length - 1).
              // val *= denominator_invs[9].
              val := mulmod(val, /*denominator_invs[9]*/ mload(0x2e60), PRIME)

              // res += val * alpha ** 53.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/last_one_is_zero: column7_row89 * (column7_row0 - (column7_row4 + column7_row4)).
              let val := mulmod(
                /*column7_row89*/ mload(0x1720),
                addmod(
                  /*column7_row0*/ mload(0x1520),
                  sub(
                    PRIME,
                    addmod(/*column7_row4*/ mload(0x15a0), /*column7_row4*/ mload(0x15a0), PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 54.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones0: column7_row89 * (column7_row4 - 3138550867693340381917894711603833208051177722232017256448 * column7_row768).
              let val := mulmod(
                /*column7_row89*/ mload(0x1720),
                addmod(
                  /*column7_row4*/ mload(0x15a0),
                  sub(
                    PRIME,
                    mulmod(
                      3138550867693340381917894711603833208051177722232017256448,
                      /*column7_row768*/ mload(0x1740),
                      PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 55.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/cumulative_bit192: column7_row89 - column7_row1022 * (column7_row768 - (column7_row772 + column7_row772)).
              let val := addmod(
                /*column7_row89*/ mload(0x1720),
                sub(
                  PRIME,
                  mulmod(
                    /*column7_row1022*/ mload(0x1800),
                    addmod(
                      /*column7_row768*/ mload(0x1740),
                      sub(
                        PRIME,
                        addmod(/*column7_row772*/ mload(0x1760), /*column7_row772*/ mload(0x1760), PRIME)),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 56.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones192: column7_row1022 * (column7_row772 - 8 * column7_row784).
              let val := mulmod(
                /*column7_row1022*/ mload(0x1800),
                addmod(
                  /*column7_row772*/ mload(0x1760),
                  sub(PRIME, mulmod(8, /*column7_row784*/ mload(0x1780), PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 57.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/cumulative_bit196: column7_row1022 - (column7_row1004 - (column7_row1008 + column7_row1008)) * (column7_row784 - (column7_row788 + column7_row788)).
              let val := addmod(
                /*column7_row1022*/ mload(0x1800),
                sub(
                  PRIME,
                  mulmod(
                    addmod(
                      /*column7_row1004*/ mload(0x17c0),
                      sub(
                        PRIME,
                        addmod(/*column7_row1008*/ mload(0x17e0), /*column7_row1008*/ mload(0x17e0), PRIME)),
                      PRIME),
                    addmod(
                      /*column7_row784*/ mload(0x1780),
                      sub(
                        PRIME,
                        addmod(/*column7_row788*/ mload(0x17a0), /*column7_row788*/ mload(0x17a0), PRIME)),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 58.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_unpacking/zeroes_between_ones196: (column7_row1004 - (column7_row1008 + column7_row1008)) * (column7_row788 - 18014398509481984 * column7_row1004).
              let val := mulmod(
                addmod(
                  /*column7_row1004*/ mload(0x17c0),
                  sub(
                    PRIME,
                    addmod(/*column7_row1008*/ mload(0x17e0), /*column7_row1008*/ mload(0x17e0), PRIME)),
                  PRIME),
                addmod(
                  /*column7_row788*/ mload(0x17a0),
                  sub(PRIME, mulmod(18014398509481984, /*column7_row1004*/ mload(0x17c0), PRIME)),
                  PRIME),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 59.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/booleanity_test: pedersen__hash0__ec_subset_sum__bit_0 * (pedersen__hash0__ec_subset_sum__bit_0 - 1).
              let val := mulmod(
                /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000),
                addmod(
                  /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000),
                  sub(PRIME, 1),
                  PRIME),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 60.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/bit_extraction_end: column7_row0.
              let val := /*column7_row0*/ mload(0x1520)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - trace_generator^(63 * trace_length / 64).
              // val *= denominator_invs[12].
              val := mulmod(val, /*denominator_invs[12]*/ mload(0x2ec0), PRIME)

              // res += val * alpha ** 61.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/zeros_tail: column7_row0.
              let val := /*column7_row0*/ mload(0x1520)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= denominator_invs[11].
              val := mulmod(val, /*denominator_invs[11]*/ mload(0x2ea0), PRIME)

              // res += val * alpha ** 62.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/add_points/slope: pedersen__hash0__ec_subset_sum__bit_0 * (column6_row3 - pedersen__points__y) - column7_row2 * (column6_row1 - pedersen__points__x).
              let val := addmod(
                mulmod(
                  /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000),
                  addmod(
                    /*column6_row3*/ mload(0x12c0),
                    sub(PRIME, /*periodic_column/pedersen/points/y*/ mload(0x20)),
                    PRIME),
                  PRIME),
                sub(
                  PRIME,
                  mulmod(
                    /*column7_row2*/ mload(0x1560),
                    addmod(
                      /*column6_row1*/ mload(0x1280),
                      sub(PRIME, /*periodic_column/pedersen/points/x*/ mload(0x0)),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 63.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/add_points/x: column7_row2 * column7_row2 - pedersen__hash0__ec_subset_sum__bit_0 * (column6_row1 + pedersen__points__x + column6_row5).
              let val := addmod(
                mulmod(/*column7_row2*/ mload(0x1560), /*column7_row2*/ mload(0x1560), PRIME),
                sub(
                  PRIME,
                  mulmod(
                    /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000),
                    addmod(
                      addmod(
                        /*column6_row1*/ mload(0x1280),
                        /*periodic_column/pedersen/points/x*/ mload(0x0),
                        PRIME),
                      /*column6_row5*/ mload(0x1300),
                      PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 64.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/add_points/y: pedersen__hash0__ec_subset_sum__bit_0 * (column6_row3 + column6_row7) - column7_row2 * (column6_row1 - column6_row5).
              let val := addmod(
                mulmod(
                  /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_0*/ mload(0x2000),
                  addmod(/*column6_row3*/ mload(0x12c0), /*column6_row7*/ mload(0x1340), PRIME),
                  PRIME),
                sub(
                  PRIME,
                  mulmod(
                    /*column7_row2*/ mload(0x1560),
                    addmod(/*column6_row1*/ mload(0x1280), sub(PRIME, /*column6_row5*/ mload(0x1300)), PRIME),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 65.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/copy_point/x: pedersen__hash0__ec_subset_sum__bit_neg_0 * (column6_row5 - column6_row1).
              let val := mulmod(
                /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_neg_0*/ mload(0x2020),
                addmod(/*column6_row5*/ mload(0x1300), sub(PRIME, /*column6_row1*/ mload(0x1280)), PRIME),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 66.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/ec_subset_sum/copy_point/y: pedersen__hash0__ec_subset_sum__bit_neg_0 * (column6_row7 - column6_row3).
              let val := mulmod(
                /*intermediate_value/pedersen/hash0/ec_subset_sum/bit_neg_0*/ mload(0x2020),
                addmod(/*column6_row7*/ mload(0x1340), sub(PRIME, /*column6_row3*/ mload(0x12c0)), PRIME),
                PRIME)

              // Numerator: point^(trace_length / 1024) - trace_generator^(255 * trace_length / 256).
              // val *= domains[16].
              val := mulmod(val, /*domains[16]*/ mload(0x2bc0), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 67.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/copy_point/x: column6_row1025 - column6_row1021.
              let val := addmod(
                /*column6_row1025*/ mload(0x14c0),
                sub(PRIME, /*column6_row1021*/ mload(0x1480)),
                PRIME)

              // Numerator: point^(trace_length / 2048) - trace_generator^(trace_length / 2).
              // val *= domains[18].
              val := mulmod(val, /*domains[18]*/ mload(0x2c00), PRIME)
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 68.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/copy_point/y: column6_row1027 - column6_row1023.
              let val := addmod(
                /*column6_row1027*/ mload(0x14e0),
                sub(PRIME, /*column6_row1023*/ mload(0x14a0)),
                PRIME)

              // Numerator: point^(trace_length / 2048) - trace_generator^(trace_length / 2).
              // val *= domains[18].
              val := mulmod(val, /*domains[18]*/ mload(0x2c00), PRIME)
              // Denominator: point^(trace_length / 1024) - 1.
              // val *= denominator_invs[10].
              val := mulmod(val, /*denominator_invs[10]*/ mload(0x2e80), PRIME)

              // res += val * alpha ** 69.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/init/x: column6_row1 - pedersen/shift_point.x.
              let val := addmod(
                /*column6_row1*/ mload(0x1280),
                sub(PRIME, /*pedersen/shift_point.x*/ mload(0x360)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 70.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/hash0/init/y: column6_row3 - pedersen/shift_point.y.
              let val := addmod(
                /*column6_row3*/ mload(0x12c0),
                sub(PRIME, /*pedersen/shift_point.y*/ mload(0x380)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 71.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/input0_value0: column3_row11 - column7_row0.
              let val := addmod(/*column3_row11*/ mload(0xcc0), sub(PRIME, /*column7_row0*/ mload(0x1520)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 72.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/input0_addr: column3_row2058 - (column3_row522 + 1).
              let val := addmod(
                /*column3_row2058*/ mload(0x1080),
                sub(PRIME, addmod(/*column3_row522*/ mload(0x1000), 1, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 2048).
              // val *= domains[25].
              val := mulmod(val, /*domains[25]*/ mload(0x2ce0), PRIME)
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 73.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/init_addr: column3_row10 - initial_pedersen_addr.
              let val := addmod(
                /*column3_row10*/ mload(0xca0),
                sub(PRIME, /*initial_pedersen_addr*/ mload(0x3a0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 74.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/input1_value0: column3_row1035 - column7_row1024.
              let val := addmod(
                /*column3_row1035*/ mload(0x1060),
                sub(PRIME, /*column7_row1024*/ mload(0x1820)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 75.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/input1_addr: column3_row1034 - (column3_row10 + 1).
              let val := addmod(
                /*column3_row1034*/ mload(0x1040),
                sub(PRIME, addmod(/*column3_row10*/ mload(0xca0), 1, PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 76.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/output_value0: column3_row523 - column6_row2045.
              let val := addmod(
                /*column3_row523*/ mload(0x1020),
                sub(PRIME, /*column6_row2045*/ mload(0x1500)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 77.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for pedersen/output_addr: column3_row522 - (column3_row1034 + 1).
              let val := addmod(
                /*column3_row522*/ mload(0x1000),
                sub(PRIME, addmod(/*column3_row1034*/ mload(0x1040), 1, PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2048) - 1.
              // val *= denominator_invs[13].
              val := mulmod(val, /*denominator_invs[13]*/ mload(0x2ee0), PRIME)

              // res += val * alpha ** 78.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check_builtin/value: range_check_builtin__value7_0 - column3_row75.
              let val := addmod(
                /*intermediate_value/range_check_builtin/value7_0*/ mload(0x2120),
                sub(PRIME, /*column3_row75*/ mload(0xec0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 79.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check_builtin/addr_step: column3_row202 - (column3_row74 + 1).
              let val := addmod(
                /*column3_row202*/ mload(0xfe0),
                sub(PRIME, addmod(/*column3_row74*/ mload(0xea0), 1, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 128).
              // val *= domains[26].
              val := mulmod(val, /*domains[26]*/ mload(0x2d00), PRIME)
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 80.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for range_check_builtin/init_addr: column3_row74 - initial_range_check_addr.
              let val := addmod(
                /*column3_row74*/ mload(0xea0),
                sub(PRIME, /*initial_range_check_addr*/ mload(0x3c0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 81.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/init_var_pool_addr: column3_row26 - initial_bitwise_addr.
              let val := addmod(
                /*column3_row26*/ mload(0xd80),
                sub(PRIME, /*initial_bitwise_addr*/ mload(0x3e0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 82.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/step_var_pool_addr: column3_row58 - (column3_row26 + 1).
              let val := addmod(
                /*column3_row58*/ mload(0xe40),
                sub(PRIME, addmod(/*column3_row26*/ mload(0xd80), 1, PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 128) - trace_generator^(3 * trace_length / 4).
              // val *= domains[9].
              val := mulmod(val, /*domains[9]*/ mload(0x2ae0), PRIME)
              // Denominator: point^(trace_length / 32) - 1.
              // val *= denominator_invs[15].
              val := mulmod(val, /*denominator_invs[15]*/ mload(0x2f20), PRIME)

              // res += val * alpha ** 83.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/x_or_y_addr: column3_row42 - (column3_row122 + 1).
              let val := addmod(
                /*column3_row42*/ mload(0xe00),
                sub(PRIME, addmod(/*column3_row122*/ mload(0xf80), 1, PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 84.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/next_var_pool_addr: column3_row154 - (column3_row42 + 1).
              let val := addmod(
                /*column3_row154*/ mload(0xfc0),
                sub(PRIME, addmod(/*column3_row42*/ mload(0xe00), 1, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 128).
              // val *= domains[26].
              val := mulmod(val, /*domains[26]*/ mload(0x2d00), PRIME)
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 85.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/partition: bitwise__sum_var_0_0 + bitwise__sum_var_8_0 - column3_row27.
              let val := addmod(
                addmod(
                  /*intermediate_value/bitwise/sum_var_0_0*/ mload(0x2140),
                  /*intermediate_value/bitwise/sum_var_8_0*/ mload(0x2160),
                  PRIME),
                sub(PRIME, /*column3_row27*/ mload(0xda0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 32) - 1.
              // val *= denominator_invs[15].
              val := mulmod(val, /*denominator_invs[15]*/ mload(0x2f20), PRIME)

              // res += val * alpha ** 86.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/or_is_and_plus_xor: column3_row43 - (column3_row91 + column3_row123).
              let val := addmod(
                /*column3_row43*/ mload(0xe20),
                sub(
                  PRIME,
                  addmod(/*column3_row91*/ mload(0xf20), /*column3_row123*/ mload(0xfa0), PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 87.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/addition_is_xor_with_and: column1_row0 + column1_row32 - (column1_row96 + column1_row64 + column1_row64).
              let val := addmod(
                addmod(/*column1_row0*/ mload(0x740), /*column1_row32*/ mload(0x960), PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(/*column1_row96*/ mload(0xa60), /*column1_row64*/ mload(0x9a0), PRIME),
                    /*column1_row64*/ mload(0x9a0),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: (point^(trace_length / 128) - trace_generator^(trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(9 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(11 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(3 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(13 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(15 * trace_length / 64)) * domain8.
              // val *= denominator_invs[16].
              val := mulmod(val, /*denominator_invs[16]*/ mload(0x2f40), PRIME)

              // res += val * alpha ** 88.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/unique_unpacking192: (column1_row88 + column1_row120) * 16 - column1_row1.
              let val := addmod(
                mulmod(
                  addmod(/*column1_row88*/ mload(0x9e0), /*column1_row120*/ mload(0xaa0), PRIME),
                  16,
                  PRIME),
                sub(PRIME, /*column1_row1*/ mload(0x760)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 89.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/unique_unpacking193: (column1_row90 + column1_row122) * 16 - column1_row65.
              let val := addmod(
                mulmod(
                  addmod(/*column1_row90*/ mload(0xa00), /*column1_row122*/ mload(0xac0), PRIME),
                  16,
                  PRIME),
                sub(PRIME, /*column1_row65*/ mload(0x9c0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 90.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/unique_unpacking194: (column1_row92 + column1_row124) * 16 - column1_row33.
              let val := addmod(
                mulmod(
                  addmod(/*column1_row92*/ mload(0xa20), /*column1_row124*/ mload(0xae0), PRIME),
                  16,
                  PRIME),
                sub(PRIME, /*column1_row33*/ mload(0x980)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 91.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for bitwise/unique_unpacking195: (column1_row94 + column1_row126) * 256 - column1_row97.
              let val := addmod(
                mulmod(
                  addmod(/*column1_row94*/ mload(0xa40), /*column1_row126*/ mload(0xb00), PRIME),
                  256,
                  PRIME),
                sub(PRIME, /*column1_row97*/ mload(0xa80)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 92.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_0/init_input_output_addr: column3_row6 - initial_poseidon_addr.
              let val := addmod(
                /*column3_row6*/ mload(0xc20),
                sub(PRIME, /*initial_poseidon_addr*/ mload(0x400)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 93.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_0/addr_input_output_step: column3_row70 - (column3_row6 + 3).
              let val := addmod(
                /*column3_row70*/ mload(0xe60),
                sub(PRIME, addmod(/*column3_row6*/ mload(0xc20), 3, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 64).
              // val *= domains[27].
              val := mulmod(val, /*domains[27]*/ mload(0x2d20), PRIME)
              // Denominator: point^(trace_length / 64) - 1.
              // val *= denominator_invs[17].
              val := mulmod(val, /*denominator_invs[17]*/ mload(0x2f60), PRIME)

              // res += val * alpha ** 94.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_1/init_input_output_addr: column3_row38 - (initial_poseidon_addr + 1).
              let val := addmod(
                /*column3_row38*/ mload(0xdc0),
                sub(PRIME, addmod(/*initial_poseidon_addr*/ mload(0x400), 1, PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 95.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_1/addr_input_output_step: column3_row102 - (column3_row38 + 3).
              let val := addmod(
                /*column3_row102*/ mload(0xf40),
                sub(PRIME, addmod(/*column3_row38*/ mload(0xdc0), 3, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 64).
              // val *= domains[27].
              val := mulmod(val, /*domains[27]*/ mload(0x2d20), PRIME)
              // Denominator: point^(trace_length / 64) - 1.
              // val *= denominator_invs[17].
              val := mulmod(val, /*denominator_invs[17]*/ mload(0x2f60), PRIME)

              // res += val * alpha ** 96.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_2/init_input_output_addr: column3_row22 - (initial_poseidon_addr + 2).
              let val := addmod(
                /*column3_row22*/ mload(0xd40),
                sub(PRIME, addmod(/*initial_poseidon_addr*/ mload(0x400), 2, PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point - 1.
              // val *= denominator_invs[4].
              val := mulmod(val, /*denominator_invs[4]*/ mload(0x2dc0), PRIME)

              // res += val * alpha ** 97.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/param_2/addr_input_output_step: column3_row86 - (column3_row22 + 3).
              let val := addmod(
                /*column3_row86*/ mload(0xee0),
                sub(PRIME, addmod(/*column3_row22*/ mload(0xd40), 3, PRIME)),
                PRIME)

              // Numerator: point - trace_generator^(trace_length - 64).
              // val *= domains[27].
              val := mulmod(val, /*domains[27]*/ mload(0x2d20), PRIME)
              // Denominator: point^(trace_length / 64) - 1.
              // val *= denominator_invs[17].
              val := mulmod(val, /*denominator_invs[17]*/ mload(0x2f60), PRIME)

              // res += val * alpha ** 98.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_rounds_state0_squaring: column8_row6 * column8_row6 - column8_row9.
              let val := addmod(
                mulmod(/*column8_row6*/ mload(0x18e0), /*column8_row6*/ mload(0x18e0), PRIME),
                sub(PRIME, /*column8_row9*/ mload(0x1920)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 99.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_rounds_state1_squaring: column8_row14 * column8_row14 - column8_row5.
              let val := addmod(
                mulmod(/*column8_row14*/ mload(0x19a0), /*column8_row14*/ mload(0x19a0), PRIME),
                sub(PRIME, /*column8_row5*/ mload(0x18c0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 100.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_rounds_state2_squaring: column8_row1 * column8_row1 - column8_row13.
              let val := addmod(
                mulmod(/*column8_row1*/ mload(0x1860), /*column8_row1*/ mload(0x1860), PRIME),
                sub(PRIME, /*column8_row13*/ mload(0x1980)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 101.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/partial_rounds_state0_squaring: column5_row0 * column5_row0 - column5_row1.
              let val := addmod(
                mulmod(/*column5_row0*/ mload(0x1120), /*column5_row0*/ mload(0x1120), PRIME),
                sub(PRIME, /*column5_row1*/ mload(0x1140)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 2) - 1.
              // val *= denominator_invs[5].
              val := mulmod(val, /*denominator_invs[5]*/ mload(0x2de0), PRIME)

              // res += val * alpha ** 102.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/partial_rounds_state1_squaring: column7_row1 * column7_row1 - column7_row3.
              let val := addmod(
                mulmod(/*column7_row1*/ mload(0x1540), /*column7_row1*/ mload(0x1540), PRIME),
                sub(PRIME, /*column7_row3*/ mload(0x1580)),
                PRIME)

              // Numerator: (point^(trace_length / 128) - trace_generator^(11 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(23 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(25 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(13 * trace_length / 16)) * (point^(trace_length / 128) - trace_generator^(27 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(7 * trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(29 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(15 * trace_length / 16)) * domain9 * domain11.
              // val *= domains[12].
              val := mulmod(val, /*domains[12]*/ mload(0x2b40), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 103.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/add_first_round_key0: column3_row7 + 2950795762459345168613727575620414179244544320470208355568817838579231751791 - column8_row6.
              let val := addmod(
                addmod(
                  /*column3_row7*/ mload(0xc40),
                  2950795762459345168613727575620414179244544320470208355568817838579231751791,
                  PRIME),
                sub(PRIME, /*column8_row6*/ mload(0x18e0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 104.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/add_first_round_key1: column3_row39 + 1587446564224215276866294500450702039420286416111469274423465069420553242820 - column8_row14.
              let val := addmod(
                addmod(
                  /*column3_row39*/ mload(0xde0),
                  1587446564224215276866294500450702039420286416111469274423465069420553242820,
                  PRIME),
                sub(PRIME, /*column8_row14*/ mload(0x19a0)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 105.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/add_first_round_key2: column3_row23 + 1645965921169490687904413452218868659025437693527479459426157555728339600137 - column8_row1.
              let val := addmod(
                addmod(
                  /*column3_row23*/ mload(0xd60),
                  1645965921169490687904413452218868659025437693527479459426157555728339600137,
                  PRIME),
                sub(PRIME, /*column8_row1*/ mload(0x1860)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 106.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_round0: column8_row22 - (poseidon__poseidon__full_rounds_state0_cubed_0 + poseidon__poseidon__full_rounds_state0_cubed_0 + poseidon__poseidon__full_rounds_state0_cubed_0 + poseidon__poseidon__full_rounds_state1_cubed_0 + poseidon__poseidon__full_rounds_state2_cubed_0 + poseidon__poseidon__full_round_key0).
              let val := addmod(
                /*column8_row22*/ mload(0x1a00),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0*/ mload(0x2180),
                            /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0*/ mload(0x2180),
                            PRIME),
                          /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0*/ mload(0x2180),
                          PRIME),
                        /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_0*/ mload(0x21a0),
                        PRIME),
                      /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_0*/ mload(0x21c0),
                      PRIME),
                    /*periodic_column/poseidon/poseidon/full_round_key0*/ mload(0x40),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 64) - trace_generator^(3 * trace_length / 4).
              // val *= domains[7].
              val := mulmod(val, /*domains[7]*/ mload(0x2aa0), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 107.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_round1: column8_row30 + poseidon__poseidon__full_rounds_state1_cubed_0 - (poseidon__poseidon__full_rounds_state0_cubed_0 + poseidon__poseidon__full_rounds_state2_cubed_0 + poseidon__poseidon__full_round_key1).
              let val := addmod(
                addmod(
                  /*column8_row30*/ mload(0x1a40),
                  /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_0*/ mload(0x21a0),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0*/ mload(0x2180),
                      /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_0*/ mload(0x21c0),
                      PRIME),
                    /*periodic_column/poseidon/poseidon/full_round_key1*/ mload(0x60),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 64) - trace_generator^(3 * trace_length / 4).
              // val *= domains[7].
              val := mulmod(val, /*domains[7]*/ mload(0x2aa0), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 108.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/full_round2: column8_row17 + poseidon__poseidon__full_rounds_state2_cubed_0 + poseidon__poseidon__full_rounds_state2_cubed_0 - (poseidon__poseidon__full_rounds_state0_cubed_0 + poseidon__poseidon__full_rounds_state1_cubed_0 + poseidon__poseidon__full_round_key2).
              let val := addmod(
                addmod(
                  addmod(
                    /*column8_row17*/ mload(0x19e0),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_0*/ mload(0x21c0),
                    PRIME),
                  /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_0*/ mload(0x21c0),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_0*/ mload(0x2180),
                      /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_0*/ mload(0x21a0),
                      PRIME),
                    /*periodic_column/poseidon/poseidon/full_round_key2*/ mload(0x80),
                    PRIME)),
                PRIME)

              // Numerator: point^(trace_length / 64) - trace_generator^(3 * trace_length / 4).
              // val *= domains[7].
              val := mulmod(val, /*domains[7]*/ mload(0x2aa0), PRIME)
              // Denominator: point^(trace_length / 16) - 1.
              // val *= denominator_invs[2].
              val := mulmod(val, /*denominator_invs[2]*/ mload(0x2d80), PRIME)

              // res += val * alpha ** 109.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/last_full_round0: column3_row71 - (poseidon__poseidon__full_rounds_state0_cubed_7 + poseidon__poseidon__full_rounds_state0_cubed_7 + poseidon__poseidon__full_rounds_state0_cubed_7 + poseidon__poseidon__full_rounds_state1_cubed_7 + poseidon__poseidon__full_rounds_state2_cubed_7).
              let val := addmod(
                /*column3_row71*/ mload(0xe80),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7*/ mload(0x21e0),
                          /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7*/ mload(0x21e0),
                          PRIME),
                        /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7*/ mload(0x21e0),
                        PRIME),
                      /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_7*/ mload(0x2200),
                      PRIME),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_7*/ mload(0x2220),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 110.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/last_full_round1: column3_row103 + poseidon__poseidon__full_rounds_state1_cubed_7 - (poseidon__poseidon__full_rounds_state0_cubed_7 + poseidon__poseidon__full_rounds_state2_cubed_7).
              let val := addmod(
                addmod(
                  /*column3_row103*/ mload(0xf60),
                  /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_7*/ mload(0x2200),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7*/ mload(0x21e0),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_7*/ mload(0x2220),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 111.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/last_full_round2: column3_row87 + poseidon__poseidon__full_rounds_state2_cubed_7 + poseidon__poseidon__full_rounds_state2_cubed_7 - (poseidon__poseidon__full_rounds_state0_cubed_7 + poseidon__poseidon__full_rounds_state1_cubed_7).
              let val := addmod(
                addmod(
                  addmod(
                    /*column3_row87*/ mload(0xf00),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_7*/ mload(0x2220),
                    PRIME),
                  /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_7*/ mload(0x2220),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_7*/ mload(0x21e0),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_7*/ mload(0x2200),
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 112.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/copy_partial_rounds0_i0: column5_row122 - column7_row1.
              let val := addmod(/*column5_row122*/ mload(0x1200), sub(PRIME, /*column7_row1*/ mload(0x1540)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 113.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/copy_partial_rounds0_i1: column5_row124 - column7_row5.
              let val := addmod(/*column5_row124*/ mload(0x1220), sub(PRIME, /*column7_row5*/ mload(0x15c0)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 114.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/copy_partial_rounds0_i2: column5_row126 - column7_row9.
              let val := addmod(/*column5_row126*/ mload(0x1240), sub(PRIME, /*column7_row9*/ mload(0x1600)), PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 115.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_full_to_partial0: column5_row0 + poseidon__poseidon__full_rounds_state2_cubed_3 + poseidon__poseidon__full_rounds_state2_cubed_3 - (poseidon__poseidon__full_rounds_state0_cubed_3 + poseidon__poseidon__full_rounds_state1_cubed_3 + 2121140748740143694053732746913428481442990369183417228688865837805149503386).
              let val := addmod(
                addmod(
                  addmod(
                    /*column5_row0*/ mload(0x1120),
                    /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_3*/ mload(0x2280),
                    PRIME),
                  /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_3*/ mload(0x2280),
                  PRIME),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      /*intermediate_value/poseidon/poseidon/full_rounds_state0_cubed_3*/ mload(0x2240),
                      /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_3*/ mload(0x2260),
                      PRIME),
                    2121140748740143694053732746913428481442990369183417228688865837805149503386,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 116.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_full_to_partial1: column5_row2 - (3618502788666131213697322783095070105623107215331596699973092056135872020477 * poseidon__poseidon__full_rounds_state1_cubed_3 + 10 * poseidon__poseidon__full_rounds_state2_cubed_3 + 4 * column5_row0 + 3618502788666131213697322783095070105623107215331596699973092056135872020479 * poseidon__poseidon__partial_rounds_state0_cubed_0 + 2006642341318481906727563724340978325665491359415674592697055778067937914672).
              let val := addmod(
                /*column5_row2*/ mload(0x1160),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          mulmod(
                            3618502788666131213697322783095070105623107215331596699973092056135872020477,
                            /*intermediate_value/poseidon/poseidon/full_rounds_state1_cubed_3*/ mload(0x2260),
                            PRIME),
                          mulmod(
                            10,
                            /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_3*/ mload(0x2280),
                            PRIME),
                          PRIME),
                        mulmod(4, /*column5_row0*/ mload(0x1120), PRIME),
                        PRIME),
                      mulmod(
                        3618502788666131213697322783095070105623107215331596699973092056135872020479,
                        /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_0*/ mload(0x22a0),
                        PRIME),
                      PRIME),
                    2006642341318481906727563724340978325665491359415674592697055778067937914672,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 117.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_full_to_partial2: column5_row4 - (8 * poseidon__poseidon__full_rounds_state2_cubed_3 + 4 * column5_row0 + 6 * poseidon__poseidon__partial_rounds_state0_cubed_0 + column5_row2 + column5_row2 + 3618502788666131213697322783095070105623107215331596699973092056135872020479 * poseidon__poseidon__partial_rounds_state0_cubed_1 + 427751140904099001132521606468025610873158555767197326325930641757709538586).
              let val := addmod(
                /*column5_row4*/ mload(0x11a0),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            addmod(
                              mulmod(
                                8,
                                /*intermediate_value/poseidon/poseidon/full_rounds_state2_cubed_3*/ mload(0x2280),
                                PRIME),
                              mulmod(4, /*column5_row0*/ mload(0x1120), PRIME),
                              PRIME),
                            mulmod(
                              6,
                              /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_0*/ mload(0x22a0),
                              PRIME),
                            PRIME),
                          /*column5_row2*/ mload(0x1160),
                          PRIME),
                        /*column5_row2*/ mload(0x1160),
                        PRIME),
                      mulmod(
                        3618502788666131213697322783095070105623107215331596699973092056135872020479,
                        /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_1*/ mload(0x22c0),
                        PRIME),
                      PRIME),
                    427751140904099001132521606468025610873158555767197326325930641757709538586,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 118.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/partial_round0: column5_row6 - (8 * poseidon__poseidon__partial_rounds_state0_cubed_0 + 4 * column5_row2 + 6 * poseidon__poseidon__partial_rounds_state0_cubed_1 + column5_row4 + column5_row4 + 3618502788666131213697322783095070105623107215331596699973092056135872020479 * poseidon__poseidon__partial_rounds_state0_cubed_2 + poseidon__poseidon__partial_round_key0).
              let val := addmod(
                /*column5_row6*/ mload(0x11e0),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            addmod(
                              mulmod(
                                8,
                                /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_0*/ mload(0x22a0),
                                PRIME),
                              mulmod(4, /*column5_row2*/ mload(0x1160), PRIME),
                              PRIME),
                            mulmod(
                              6,
                              /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_1*/ mload(0x22c0),
                              PRIME),
                            PRIME),
                          /*column5_row4*/ mload(0x11a0),
                          PRIME),
                        /*column5_row4*/ mload(0x11a0),
                        PRIME),
                      mulmod(
                        3618502788666131213697322783095070105623107215331596699973092056135872020479,
                        /*intermediate_value/poseidon/poseidon/partial_rounds_state0_cubed_2*/ mload(0x22e0),
                        PRIME),
                      PRIME),
                    /*periodic_column/poseidon/poseidon/partial_round_key0*/ mload(0xa0),
                    PRIME)),
                PRIME)

              // Numerator: (point^(trace_length / 128) - trace_generator^(61 * trace_length / 64)) * (point^(trace_length / 128) - trace_generator^(63 * trace_length / 64)) * domain11.
              // val *= domains[13].
              val := mulmod(val, /*domains[13]*/ mload(0x2b60), PRIME)
              // Denominator: point^(trace_length / 2) - 1.
              // val *= denominator_invs[5].
              val := mulmod(val, /*denominator_invs[5]*/ mload(0x2de0), PRIME)

              // res += val * alpha ** 119.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/partial_round1: column7_row13 - (8 * poseidon__poseidon__partial_rounds_state1_cubed_0 + 4 * column7_row5 + 6 * poseidon__poseidon__partial_rounds_state1_cubed_1 + column7_row9 + column7_row9 + 3618502788666131213697322783095070105623107215331596699973092056135872020479 * poseidon__poseidon__partial_rounds_state1_cubed_2 + poseidon__poseidon__partial_round_key1).
              let val := addmod(
                /*column7_row13*/ mload(0x1640),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            addmod(
                              mulmod(
                                8,
                                /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_0*/ mload(0x2300),
                                PRIME),
                              mulmod(4, /*column7_row5*/ mload(0x15c0), PRIME),
                              PRIME),
                            mulmod(
                              6,
                              /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_1*/ mload(0x2320),
                              PRIME),
                            PRIME),
                          /*column7_row9*/ mload(0x1600),
                          PRIME),
                        /*column7_row9*/ mload(0x1600),
                        PRIME),
                      mulmod(
                        3618502788666131213697322783095070105623107215331596699973092056135872020479,
                        /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_2*/ mload(0x2340),
                        PRIME),
                      PRIME),
                    /*periodic_column/poseidon/poseidon/partial_round_key1*/ mload(0xc0),
                    PRIME)),
                PRIME)

              // Numerator: (point^(trace_length / 128) - trace_generator^(19 * trace_length / 32)) * (point^(trace_length / 128) - trace_generator^(5 * trace_length / 8)) * (point^(trace_length / 128) - trace_generator^(21 * trace_length / 32)) * domain12.
              // val *= domains[14].
              val := mulmod(val, /*domains[14]*/ mload(0x2b80), PRIME)
              // Denominator: point^(trace_length / 4) - 1.
              // val *= denominator_invs[7].
              val := mulmod(val, /*denominator_invs[7]*/ mload(0x2e20), PRIME)

              // res += val * alpha ** 120.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_partial_to_full0: column8_row70 - (16 * poseidon__poseidon__partial_rounds_state1_cubed_19 + 8 * column7_row81 + 16 * poseidon__poseidon__partial_rounds_state1_cubed_20 + 6 * column7_row85 + poseidon__poseidon__partial_rounds_state1_cubed_21 + 560279373700919169769089400651532183647886248799764942664266404650165812023).
              let val := addmod(
                /*column8_row70*/ mload(0x1b40),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            mulmod(
                              16,
                              /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_19*/ mload(0x2360),
                              PRIME),
                            mulmod(8, /*column7_row81*/ mload(0x16a0), PRIME),
                            PRIME),
                          mulmod(
                            16,
                            /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_20*/ mload(0x2380),
                            PRIME),
                          PRIME),
                        mulmod(6, /*column7_row85*/ mload(0x16e0), PRIME),
                        PRIME),
                      /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_21*/ mload(0x23a0),
                      PRIME),
                    560279373700919169769089400651532183647886248799764942664266404650165812023,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 121.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_partial_to_full1: column8_row78 - (4 * poseidon__poseidon__partial_rounds_state1_cubed_20 + column7_row85 + column7_row85 + poseidon__poseidon__partial_rounds_state1_cubed_21 + 1401754474293352309994371631695783042590401941592571735921592823982231996415).
              let val := addmod(
                /*column8_row78*/ mload(0x1b60),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          mulmod(
                            4,
                            /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_20*/ mload(0x2380),
                            PRIME),
                          /*column7_row85*/ mload(0x16e0),
                          PRIME),
                        /*column7_row85*/ mload(0x16e0),
                        PRIME),
                      /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_21*/ mload(0x23a0),
                      PRIME),
                    1401754474293352309994371631695783042590401941592571735921592823982231996415,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 122.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

              {
              // Constraint expression for poseidon/poseidon/margin_partial_to_full2: column8_row65 - (8 * poseidon__poseidon__partial_rounds_state1_cubed_19 + 4 * column7_row81 + 6 * poseidon__poseidon__partial_rounds_state1_cubed_20 + column7_row85 + column7_row85 + 3618502788666131213697322783095070105623107215331596699973092056135872020479 * poseidon__poseidon__partial_rounds_state1_cubed_21 + 1246177936547655338400308396717835700699368047388302793172818304164989556526).
              let val := addmod(
                /*column8_row65*/ mload(0x1b20),
                sub(
                  PRIME,
                  addmod(
                    addmod(
                      addmod(
                        addmod(
                          addmod(
                            addmod(
                              mulmod(
                                8,
                                /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_19*/ mload(0x2360),
                                PRIME),
                              mulmod(4, /*column7_row81*/ mload(0x16a0), PRIME),
                              PRIME),
                            mulmod(
                              6,
                              /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_20*/ mload(0x2380),
                              PRIME),
                            PRIME),
                          /*column7_row85*/ mload(0x16e0),
                          PRIME),
                        /*column7_row85*/ mload(0x16e0),
                        PRIME),
                      mulmod(
                        3618502788666131213697322783095070105623107215331596699973092056135872020479,
                        /*intermediate_value/poseidon/poseidon/partial_rounds_state1_cubed_21*/ mload(0x23a0),
                        PRIME),
                      PRIME),
                    1246177936547655338400308396717835700699368047388302793172818304164989556526,
                    PRIME)),
                PRIME)

              // Numerator: 1.
              // val *= 1.
              // Denominator: point^(trace_length / 128) - 1.
              // val *= denominator_invs[14].
              val := mulmod(val, /*denominator_invs[14]*/ mload(0x2f00), PRIME)

              // res += val * alpha ** 123.
              res := addmod(res, mulmod(val, composition_alpha_pow, PRIME), PRIME)
              composition_alpha_pow := mulmod(composition_alpha_pow, composition_alpha, PRIME)
              }

            mstore(0, res)
            return(0, 0x20)
            }
        }
    }
}
// ---------- End of auto-generated code. ----------
