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

import "./PageInfo.sol";

contract CpuPublicInputOffsetsBase is PageInfo {
    // The following constants are offsets of data expected in the public input.
    uint256 internal constant OFFSET_N_VERIFIER_FRIENDLY_LAYERS = 0;
    uint256 internal constant OFFSET_LOG_N_STEPS = 1;
    uint256 internal constant OFFSET_RC_MIN = 2;
    uint256 internal constant OFFSET_RC_MAX = 3;
    uint256 internal constant OFFSET_LAYOUT_CODE = 4;
    uint256 internal constant OFFSET_PROGRAM_BEGIN_ADDR = 5;
    uint256 internal constant OFFSET_PROGRAM_STOP_PTR = 6;
    uint256 internal constant OFFSET_EXECUTION_BEGIN_ADDR = 7;
    uint256 internal constant OFFSET_EXECUTION_STOP_PTR = 8;
    uint256 internal constant OFFSET_OUTPUT_BEGIN_ADDR = 9;
    uint256 internal constant OFFSET_OUTPUT_STOP_PTR = 10;
    uint256 internal constant OFFSET_PEDERSEN_BEGIN_ADDR = 11;
    uint256 internal constant OFFSET_PEDERSEN_STOP_PTR = 12;
    uint256 internal constant OFFSET_RANGE_CHECK_BEGIN_ADDR = 13;
    uint256 internal constant OFFSET_RANGE_CHECK_STOP_PTR = 14;
    // The program segment starts from 1, so that memory address 0 is kept for the null pointer.
    uint256 internal constant INITIAL_PC = 1;
    // The first Cairo instructions are:
    //   ap += n_args; call main; jmp rel 0.
    // As the first two instructions occupy 2 cells each, the "jmp rel 0" instruction is at
    // offset 4 relative to INITIAL_PC.
    uint256 internal constant FINAL_PC = INITIAL_PC + 4;
}
// ---------- End of auto-generated code. ----------
