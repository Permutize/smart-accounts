// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.23;

contract TestCounter {
    mapping(address => uint256) public counters;

    function count() public {
        counters[msg.sender] = counters[msg.sender] + 1;
    }

    function revertWithReason(string memory reason) public pure {
        revert(reason);
    }

    function revertWithoutReason() public pure {
        revert();
    }

    event CalledFrom(address sender);
}
