// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.23;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IFeeManager } from "../src/interfaces/IFeeManager.sol";
import { IBaseAccount } from "../src/interfaces/IBaseAccount.sol";
import { MetaAccount } from "../src/account/MetaAccount.sol";
import { FeeManager } from "../src/core/FeeManager.sol";
import { BaseAccountTest } from "./BaseAccountTest.t.sol";
import { TestERC20 } from "../utils/test/TestToken.sol";

contract MetaAccountTest is BaseAccountTest {
    string private constant DOMAIN_NAME = "MetaAccount";
    string private constant DOMAIN_VERSION = "1";

    MetaAccount public metaAccount;
    FeeManager public feeManager;

    function createAccount(address owner, address nonceManager) internal override returns (IBaseAccount) {
        // Create FeeManager with token configurations
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: token, decimals: token.decimals(), enabled: true, minFeeCost: 1000, maxFeeCost: 1000 * 1e6
        });

        feeManager = new FeeManager(owner);

        // Add supported tokens
        vm.startPrank(owner);
        feeManager.addTokens(tokenConfigs);
        vm.stopPrank();

        metaAccount = new MetaAccount(owner, nonceManager, address(feeManager));
        return IBaseAccount(address(metaAccount));
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

    // ============ Constructor Tests ============

    /**
     * @notice Test MetaAccount constructor with valid parameters
     */
    function test_Constructor_Success() public {
        address testOwner = makeAddr("testOwner");

        // First create the fee manager
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: token, decimals: token.decimals(), enabled: true, minFeeCost: 1000, maxFeeCost: 100_000
        });

        FeeManager testFeeManager = new FeeManager(testOwner);

        // Add supported tokens
        vm.prank(testOwner);
        testFeeManager.addTokens(tokenConfigs);
        vm.stopPrank();

        MetaAccount testAccount = new MetaAccount(testOwner, address(nonceManager), address(testFeeManager));

        assertEq(address(testAccount.FEE_MANAGER()), address(testFeeManager), "Fee manager should be set correctly");
        assertEq(testAccount.owner(), testOwner, "Owner should be set correctly");
    }

    /**
     * @notice Test MetaAccount constructor reverts with zero fee manager address
     */
    function test_Constructor_RevertInvalidFeeManager() public {
        address testOwner = makeAddr("testOwner");

        vm.expectRevert(MetaAccount.InvalidFeeManager.selector);
        new MetaAccount(testOwner, address(nonceManager), address(0));
    }

    // ============ Fee Validation Tests ============

    /**
     * @notice Test successful meta-transaction execution with valid fee payment
     */
    function test_Execute_ValidFeeCall_Success() public runWithSponsor {
        // Fund the account with tokens for fee payment
        token.sudoMint(user, 1000 * 10 ** 18);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: valid fee payment
        calls[0] = _createFeePaymentCall(1e3);
        // Second call: counter increment
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(IBaseAccount(user).nonce(user), block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialCount = counter.counters(user);
        uint256 balanceBefore = token.balanceOf(user);
        executeCallsByOwner(batch, signature);
        assertEq(counter.counters(user), initialCount + 1, "Counter should be incremented");
        assertGe(token.balanceOf(address(feeManager)), 1000, "Fee should be transferred to FeeManager");
        assertEq(token.balanceOf(user), balanceBefore - 1000, "User should pay the fee");
    }

    /**
     * @notice Test meta-transaction execution reverts with invalid fee call (wrong token)
     */
    function test_Execute_InvalidFeeCall_WrongToken_Reverts() public runWithSponsor {
        // Create a different token that's not enabled in FeeManager
        TestERC20 wrongToken = new TestERC20(18);
        wrongToken.sudoMint(user, 1000 * 10 ** 18);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: invalid fee payment (wrong token)
        calls[0] = _createCall(
            address(wrongToken),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, address(feeManager), 100 * 10 ** 18)
        );
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test meta-transaction execution reverts with invalid fee call (wrong recipient)
     */
    function test_Execute_InvalidFeeCall_WrongRecipient_Reverts() public runWithSponsor {
        token.sudoMint(user, 1000 * 10 ** 18);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: invalid fee payment (wrong recipient)
        calls[0] = _createCall(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, owner, 100 * 10 ** 18) // Wrong recipient
        );
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test meta-transaction execution reverts with invalid fee call (wrong function selector)
     */
    function test_Execute_InvalidFeeCall_WrongSelector_Reverts() public runWithSponsor {
        token.sudoMint(user, 1000 * 10 ** 18);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: invalid fee payment (wrong selector)
        calls[0] = _createCall(
            address(token),
            0,
            abi.encodeWithSelector(IERC20.approve.selector, address(feeManager), 100 * 10 ** 18) // Wrong selector
        );
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test meta-transaction execution reverts when token is disabled
     */
    function test_Execute_InvalidFeeCall_DisabledToken_Reverts() public runWithSponsor {
        token.sudoMint(user, 1000 * 10 ** 18);

        // Disable the token in FeeManager
        feeManager.setTokenEnabled(address(token), false);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        calls[0] = _createFeePaymentCall(100 * 10 ** 18);
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test meta-transaction execution reverts with fee amount below minimum
     */
    function test_Execute_InvalidFeeCall_AmountTooLow_Reverts() public runWithSponsor {
        token.sudoMint(user, 1000 * 10 ** 18);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: fee payment below minimum (minFeeCost is 1000)
        calls[0] = _createFeePaymentCall(999); // Below minimum
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test meta-transaction execution reverts with fee amount above maximum
     */
    function test_Execute_InvalidFeeCall_AmountTooHigh_Reverts() public runWithSponsor {
        uint256 excessiveAmount = 1000 * 1e6 + 1; // Above maximum (maxFeeCost is 1000 * 1e6)
        token.sudoMint(user, excessiveAmount);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: fee payment above maximum
        calls[0] = _createFeePaymentCall(excessiveAmount);
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert(MetaAccount.InvalidFeeCall.selector);
        executeCallsByOwner(batch, signature);
    }

    // ============ Edge Cases ============
    /**
     * @notice Test meta-transaction execution with malformed fee call data
     */
    function test_Execute_MalformedFeeCallData_Reverts() public runWithSponsor {
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](2);
        // First call: malformed data (too short)
        calls[0] = _createCall(address(token), 0, abi.encode(IERC20.transfer.selector));
        calls[1] = _createCounterIncrementCall();

        IBaseAccount.Batch memory batch = _createBatch(12_345, block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);

        vm.expectRevert();
        executeCallsByOwner(batch, signature);
    }

    /**
     * @notice Test that direct execution bypasses fee validation
     */
    function test_Execute_DirectCall_BypassesFeeValidation() public runWithUser {
        // Direct execution should not require fee payment
        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1);
        calls[0] = _createCounterIncrementCall(); // No fee payment

        uint256 initialCount = counter.counters(user);
        executeDirectCalls(calls, user);

        assertEq(counter.counters(user), initialCount + 1, "Counter should be incremented without fee payment");
    }

    /**
     * @notice Test fee validation with large fee amount
     */
    function test_Execute_LargeFeeAmount_Success() public runWithSponsor {
        uint256 amount = 1e3;
        token.sudoMint(user, amount);

        IBaseAccount.Call[] memory calls = new IBaseAccount.Call[](1e4);
        calls[0] = _createFeePaymentCall(amount);
        for (uint256 i = 1; i < calls.length; i++) {
            calls[i] = _createCounterIncrementCall();
        }

        IBaseAccount.Batch memory batch = _createBatch(IBaseAccount(user).nonce(user), block.timestamp + 1 hours, calls);

        bytes memory signature = _signBatch(batch, user, userKey);
        uint256 initialCount = counter.counters(user);

        executeCallsByOwner(batch, signature);

        assertEq(counter.counters(user), initialCount + calls.length - 1, "Counter should be incremented");
        assertEq(token.balanceOf(address(feeManager)), amount, "Large fee should be transferred");
    }

    // ============ Helper Functions ============

    /**
     * @notice Helper function to create a valid fee payment call
     */
    function _createFeePaymentCall(uint256 amount) internal view returns (IBaseAccount.Call memory) {
        return
            _createCall(
                address(token), 0, abi.encodeWithSelector(IERC20.transfer.selector, address(feeManager), amount)
            );
    }
}
