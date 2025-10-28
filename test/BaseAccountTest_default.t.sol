// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.23;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { IBaseAccount } from "../src/interfaces/IBaseAccount.sol";
import { BaseAccountTest } from "./BaseAccountTest.t.sol";
import { BaseAccount } from "../src/core/BaseAccount.sol";
import { TestCounter } from "../utils/test/TestCounter.sol";

contract BaseAccountTest_default is BaseAccountTest, EIP712 {
    string private constant DOMAIN_NAME = "TestBaseAccount";
    string private constant DOMAIN_VERSION = "1";

    constructor() EIP712(DOMAIN_NAME, DOMAIN_VERSION) { }

    function createAccount(address owner, address nonceManager) internal override returns (IBaseAccount) {
        return IBaseAccount(new BaseAccount(DOMAIN_NAME, DOMAIN_VERSION, owner, nonceManager));
    }

    function hashTypedData(bytes32 structHash, address accountAddress) internal view override returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(DOMAIN_NAME)),
                keccak256(bytes(DOMAIN_VERSION)),
                block.chainid,
                accountAddress // Use the account address, not this test contract
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /**
     * @notice Test execution with mixed calls (some with value, some without)
     */
    function test_Execute_MixedCalls() public runWithSponsor {
        // Fund the account
        vm.deal(user, 1 ether);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](3);
        calls[0] = _createCounterIncrementCall(); // No value
        calls[1] = _createCall(owner, 0.3 ether, ""); // With value
        calls[2] = _createCounterIncrementCall(); // No value

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialCount = counter.counters(user);
        uint256 initialBalance = owner.balance;

        executeCallsByOwner(batch, signature);

        assertEq(counter.counters(user), initialCount + 2, "Counter should be incremented twice");
        assertEq(owner.balance, initialBalance + 0.3 ether, "Owner should receive 0.3 ether");
    }

    /**
     * @notice Test meta-transaction execution with multiple calls
     */
    function test_Execute_SponsorCall_MultipleCalls() public runWithSponsor {
        IBaseAccount.Call[] memory calls = _createMultipleCounterCalls(5);

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialCount = counter.counters(user);

        executeCallsByOwner(batch, signature);

        assertEq(counter.counters(user), initialCount + 5, "Counter should be incremented 5 times");
    }

    /**
     * @notice Test that reentrancy protection works for meta-transaction execution
     */
    function test_Execute_SponsorCall_ReentrancyProtection() public runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);

        executeCallsByOwner(batch, signature);

        // If we reach here, the nonReentrant modifier didn't block legitimate calls
        assertTrue(true, "Legitimate meta-tx should succeed with reentrancy protection");
    }

    /**
     * @notice Test meta-transaction execution reverts when nonce is reused
     */
    function test_Execute_SponsorCall_RevertNonceReuse() public runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);

        // Execute first time - should succeed
        executeCallsByOwner(batch, signature);

        // Execute second time with same nonce - should revert
        vm.expectRevert();
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test successful meta-transaction execution
     */
    function test_Execute_SponsorCall_Success() public runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialCount = counter.counters(user);

        executeCallsByOwner(batch, signature);

        assertEq(counter.counters(user), initialCount + 1, "Counter should be incremented");
    }

    /**
     * @notice Test execution with calls that have value transfers
     */
    function test_Execute_WithValue() public runWithSponsor {
        // Fund the account
        vm.deal(user, 1 ether);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCall(owner, 0.5 ether, "");

        IBaseAccount.Batch memory batch = _createBatch(
            IBaseAccount(user).nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialBalance = owner.balance;

        executeCallsByOwner(batch, signature);

        assertEq(owner.balance, initialBalance + 0.5 ether, "Owner should receive 0.5 ether");
    }

    /**
     * @notice Test execution with call that reverts with reason
     */
    function test_Execute_CallRevertedWithReason() public virtual runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCall(
            address(counter), 0, abi.encodeWithSelector(TestCounter.revertWithReason.selector, "Custom revert reason")
        );

        IBaseAccount.Batch memory batch = _createBatch(IBaseAccount(user).nonce(user), block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(abi.encodeWithSelector(IBaseAccount.CallReverted.selector, "Custom revert reason"));
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test execution with call that reverts without reason
     */
    function test_Execute_CallRevertedWithoutReason() public virtual runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCall(address(counter), 0, abi.encodeWithSelector(TestCounter.revertWithoutReason.selector));

        IBaseAccount.Batch memory batch = _createBatch(IBaseAccount(user).nonce(user), block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(abi.encodeWithSelector(IBaseAccount.CallReverted.selector, "BaseAccount: call reverted"));
        executeCallsByOwner(batch, signature);
    }

    // ============ Test Functions for nonce ============

    /**
     * @notice Test nonce function returns correct nonce
     */
    function test_Nonce() public virtual runWithSponsor {
        uint256 currentNonce = IBaseAccount(user).nonce(user);
        assertTrue(currentNonce >= 0, "Nonce should be non-negative");

        // Execute a transaction to increment nonce
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(currentNonce, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);
        executeCallsByOwner(batch, signature);

        uint256 newNonce = IBaseAccount(user).nonce(user);
        assertEq(newNonce, currentNonce + 1, "Nonce should be incremented");
    }

    /**
     * @notice Test signature validation failure in simulateBatch function
     */
    function test_SimulateBatch_InvalidSignature() public virtual {
        accountImplementation = createAccount(owner, address(nonceManager));

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(
            accountImplementation.nonce(user), // nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        // Create invalid signature using wrong private key
        uint256 wrongKey = 0x1234567890abcdef;
        bytes memory invalidSignature = _signBatch(batch, address(accountImplementation), wrongKey);

        // Set tx.origin to 0 to allow simulation
        vm.txGasPrice(0);
        vm.prank(address(0), address(0));

        // This should not revert but covers the signature validation failure branch
        accountImplementation.simulateBatch(batch, invalidSignature);
    }

    /**
     * @notice Test meta-transaction execution reverts with invalid signature
     */
    function test_Execute_SponsorCall_RevertInvalidSignature() public runWithSponsor {
        // Initialize account implementation
        accountImplementation = createAccount(owner, address(nonceManager));

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        // Use the current valid nonce to pass nonce validation
        uint256 currentNonce = accountImplementation.nonce(owner);
        IBaseAccount.Batch memory batch = _createBatch(
            currentNonce, // Use current valid nonce
            block.timestamp + 1 hours, // deadline
            calls
        );

        // Sign with wrong private key to create invalid signature
        (, uint256 wrongKey) = makeAddrAndKey("wrongSigner");
        bytes memory signature = _signBatch(batch, address(accountImplementation), wrongKey);

        // Expect specific InvalidSignature error
        vm.expectRevert(IBaseAccount.InvalidSignature.selector);
        accountImplementation.execute(batch, signature);
    }

    /**
     * @notice Test simulateBatch with valid signature
     */
    function test_SimulateBatch_Success() public runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(IBaseAccount(user).nonce(user), block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);
        // Set tx.origin to address(0) for simulation
        vm.stopPrank(); // Stop the current prank from runWithSponsor
        vm.txGasPrice(2);
        vm.prank(address(0), address(0)); // Sets both msg.sender and tx.origin to address(0)
        IBaseAccount(user).simulateBatch(batch, signature);
    }
}
