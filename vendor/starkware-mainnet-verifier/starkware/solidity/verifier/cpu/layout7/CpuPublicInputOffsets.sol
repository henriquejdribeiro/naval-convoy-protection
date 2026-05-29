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

import "../CpuPublicInputOffsetsBase.sol";

contract CpuPublicInputOffsets is CpuPublicInputOffsetsBase {
    // The following constants are offsets of data expected in the public input.
    uint256 internal constant OFFSET_BITWISE_BEGIN_ADDR = 15;
    uint256 internal constant OFFSET_BITWISE_STOP_PTR = 16;
    uint256 internal constant OFFSET_POSEIDON_BEGIN_ADDR = 17;
    uint256 internal constant OFFSET_POSEIDON_STOP_PTR = 18;
    uint256 internal constant OFFSET_PUBLIC_MEMORY_PADDING_ADDR = 19;
    uint256 internal constant OFFSET_PUBLIC_MEMORY_PADDING_VALUE = 20;
    uint256 internal constant OFFSET_N_PUBLIC_MEMORY_PAGES = 21;
    uint256 internal constant OFFSET_PUBLIC_MEMORY = 22;

    // The format of the public input, starting at OFFSET_PUBLIC_MEMORY is as follows:
    //   * For each page:
    //     * First address in the page (this field is not included for the first page).
    //     * Page size.
    //     * Page hash.
    //   # All data above this line, appears in the initial seed of the proof.
    //   * For each page:
    //     * Cumulative product.
}
// ---------- End of auto-generated code. ----------
