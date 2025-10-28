// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity >=0.8.0 <0.9.0;

import { Test } from "forge-std/Test.sol";

contract BaseTest is Test {
    modifier fork(string memory network) {
        vm.createSelectFork(network);
        _;
    }
}
