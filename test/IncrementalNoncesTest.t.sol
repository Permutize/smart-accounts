// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IncrementalNonces } from "../src/core/IncrementalNonces.sol";
import { IIncrementalNonces } from "../src/interfaces/IIncrementalNonces.sol";
import { BaseTest } from "../utils/test/BaseTest.sol";

contract IncrementalNoncesTest is BaseTest {
    IncrementalNonces nonceManager;
    address owner = address(0xA11CE);
    address user1 = address(0xBEEF);
    address user2 = address(0xCAFE);

    function setUp() public {
        vm.prank(owner);
        nonceManager = new IncrementalNonces(owner);
    }

    // Covers nonce() initial and post-consumption behavior
    function test_Nonce_InitialAndAfterConsumption() public {
        assertEq(nonceManager.nonce(user1), 0, "initial nonce should be 0");

        // Consume via owner-only path for user1
        vm.prank(owner);
        uint256 consumed = nonceManager.useNonce(user1);
        assertEq(consumed, 0, "first consumed nonce should return 0");
        assertEq(nonceManager.nonce(user1), 1, "nonce should increment to 1");

        // Consume again
        vm.prank(owner);
        uint256 consumed2 = nonceManager.useNonce(user1);
        assertEq(consumed2, 1, "second consumed nonce should return 1");
        assertEq(nonceManager.nonce(user1), 2, "nonce should increment to 2");
    }

    // Test useNonce() and x++ semantics for caller
    function test_UseNonce_CallerSemantics() public {
        // user1 consumes own nonce
        vm.prank(user1);
        uint256 first = nonceManager.useNonce();
        assertEq(first, 0, "first own nonce should be 0");
        assertEq(nonceManager.nonce(user1), 1, "next unused nonce should be 1");

        // user1 consumes again
        vm.prank(user1);
        uint256 second = nonceManager.useNonce();
        assertEq(second, 1, "second own nonce should be 1");
        assertEq(nonceManager.nonce(user1), 2, "next unused nonce should be 2");
    }

    // Test owner-only useNonce(address) access control
    function test_UseNonce_OwnerOnlyForOthers() public {
        // non-owner tries to consume another user's nonce -> should revert with Ownable
        vm.expectRevert();
        vm.prank(user2);
        nonceManager.useNonce(user1);

        // owner can consume user1's nonce
        vm.prank(owner);
        uint256 consumed = nonceManager.useNonce(user1);
        assertEq(consumed, 0, "owner consumes user1 first nonce: 0");
        assertEq(nonceManager.nonce(user1), 1, "user1 next nonce should be 1");
    }

    // Test useCheckedNonce success and InvalidNonce revert
    function test_UseCheckedNonce_Caller_SuccessAndRevert() public {
        // success path: expected 0
        vm.prank(user1);
        nonceManager.useCheckedNonce(0);
        assertEq(nonceManager.nonce(user1), 1, "after checked consume, next should be 1");

        // revert path: expected 0 but next is 1; current=1
        vm.expectRevert(abi.encodeWithSelector(IIncrementalNonces.InvalidNonce.selector, 1));
        vm.prank(user1);
        nonceManager.useCheckedNonce(0);
    }

    // Test useCheckedNonce(owner, checked) success and InvalidNonce revert
    function test_UseCheckedNonce_OwnerForOthers_SuccessAndRevert() public {
        // success path: expected 0 for user2
        vm.prank(owner);
        nonceManager.useCheckedNonce(user2, 0);
        assertEq(nonceManager.nonce(user2), 1, "user2 next nonce should be 1");

        // revert path: expected 0 but next is 1; current=1
        vm.expectRevert(abi.encodeWithSelector(IIncrementalNonces.InvalidNonce.selector, 1));
        vm.prank(owner);
        nonceManager.useCheckedNonce(user2, 0);
    }

    // Validate per-address isolation across multiple accounts
    function test_PerAddressIsolation() public {
        // user1 consumes two
        vm.prank(user1);
        assertEq(nonceManager.useNonce(), 0, "user1 first=0");
        vm.prank(user1);
        assertEq(nonceManager.useNonce(), 1, "user1 second=1");

        // user2 should still be at 0
        assertEq(nonceManager.nonce(user2), 0, "user2 initial should be 0");

        // owner consumes user2
        vm.prank(owner);
        assertEq(nonceManager.useNonce(user2), 0, "owner consumes user2 first=0");

        // user1 and user2 have independent counters
        assertEq(nonceManager.nonce(user1), 2, "user1 next should be 2");
        assertEq(nonceManager.nonce(user2), 1, "user2 next should be 1");
    }
}
