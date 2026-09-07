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

import "../../PrimeFieldElement0.sol";

contract StarkParameters is PrimeFieldElement0 {
    uint256 constant internal N_COEFFICIENTS = 124;
    uint256 constant internal N_INTERACTION_ELEMENTS = 6;
    uint256 constant internal MASK_SIZE = 192;
    uint256 constant internal N_ROWS_IN_MASK = 98;
    uint256 constant internal N_COLUMNS_IN_MASK = 12;
    uint256 constant internal N_COLUMNS_IN_TRACE0 = 9;
    uint256 constant internal N_COLUMNS_IN_TRACE1 = 3;
    uint256 constant internal CONSTRAINTS_DEGREE_BOUND = 2;
    uint256 constant internal N_OODS_VALUES = MASK_SIZE + CONSTRAINTS_DEGREE_BOUND;
    uint256 constant internal N_OODS_COEFFICIENTS = N_OODS_VALUES;

    // ---------- // Air specific constants. ----------
    uint256 constant internal PUBLIC_MEMORY_STEP = 16;
    uint256 constant internal DILUTED_SPACING = 4;
    uint256 constant internal DILUTED_N_BITS = 16;
    uint256 constant internal PEDERSEN_BUILTIN_RATIO = 128;
    uint256 constant internal PEDERSEN_BUILTIN_ROW_RATIO = 2048;
    uint256 constant internal PEDERSEN_BUILTIN_REPETITIONS = 1;
    uint256 constant internal RANGE_CHECK_BUILTIN_RATIO = 8;
    uint256 constant internal RANGE_CHECK_BUILTIN_ROW_RATIO = 128;
    uint256 constant internal RANGE_CHECK_N_PARTS = 8;
    uint256 constant internal BITWISE__RATIO = 8;
    uint256 constant internal BITWISE__ROW_RATIO = 128;
    uint256 constant internal POSEIDON__RATIO = 8;
    uint256 constant internal POSEIDON__ROW_RATIO = 128;
    uint256 constant internal POSEIDON__M = 3;
    uint256 constant internal POSEIDON__ROUNDS_FULL = 8;
    uint256 constant internal POSEIDON__ROUNDS_PARTIAL = 83;
    uint256 constant internal LAYOUT_CODE = 42800643258479064999893963318903811951182475189843316;
    uint256 constant internal LOG_CPU_COMPONENT_HEIGHT = 4;
}
// ---------- End of auto-generated code. ----------
