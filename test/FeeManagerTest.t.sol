// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FeeManager } from "../src/core/FeeManager.sol";
import { IFeeManager } from "../src/interfaces/IFeeManager.sol";
import { TestERC20 } from "../utils/test/TestToken.sol";
import { BaseTest } from "../utils/test/BaseTest.sol";

contract FeeManagerTest is BaseTest {
    FeeManager public feeManager;
    TestERC20 public token;
    TestERC20 public secondToken;
    TestERC20 public highDecimalToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        // Create test tokens
        token = new TestERC20(18);
        secondToken = new TestERC20(6);
        highDecimalToken = new TestERC20(77); // Maximum allowed decimals

        // Create token configurations
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](2);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)),
            decimals: token.decimals(),
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });
        tokenConfigs[1] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(secondToken)),
            decimals: secondToken.decimals(),
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        // Deploy FeeManager
        feeManager = new FeeManager(owner);
        vm.startPrank(owner);
        // Add supported tokens
        feeManager.addTokens(tokenConfigs);
        vm.stopPrank();

        // Mint tokens for testing
        token.sudoMint(user, 1000 * 10 ** 18);
        secondToken.sudoMint(user, 1000 * 10 ** 6);
        token.sudoMint(address(feeManager), 500 * 10 ** 18);
        secondToken.sudoMint(address(feeManager), 500 * 10 ** 6);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CONSTRUCTOR TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_Constructor_Success() public view {
        // Verify immutable values
        // Verify token configurations
        IFeeManager.TokenConfig memory tokenConfig = feeManager.supportedTokens(address(token));
        assertEq(address(tokenConfig.token), address(token));
        assertEq(tokenConfig.decimals, token.decimals());
        assertTrue(tokenConfig.enabled);

        // Verify owner
        assertEq(feeManager.owner(), owner);
    }

    function test_Constructor_InvalidTokenAddress_Reverts() public {
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(0)), // Invalid token address
            decimals: 18,
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });
        vm.expectRevert(IFeeManager.InvalidTokenAddress.selector);
        vm.startPrank(owner);
        feeManager.addTokens(tokenConfigs);
        vm.stopPrank();
    }

    function test_Constructor_TokenDecimalsTooHigh_Reverts() public {
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(new TestERC20(78))),
            decimals: 78, // Too high
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        vm.expectRevert(IFeeManager.TokenDecimalsTooHigh.selector);

        vm.startPrank(owner);
        feeManager.addTokens(tokenConfigs);
        vm.stopPrank();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   TOKEN MANAGEMENT TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_AddTokens_Success() public {
        TestERC20 newToken = new TestERC20(12);
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(newToken)),
            decimals: newToken.decimals(),
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        vm.expectEmit(true, false, true, true);
        emit IFeeManager.TokenAdded(address(newToken), newToken.decimals());

        vm.prank(owner);
        feeManager.addTokens(tokenConfigs);

        IFeeManager.TokenConfig memory config = feeManager.supportedTokens(address(newToken));
        assertEq(address(config.token), address(newToken));
        assertEq(config.decimals, newToken.decimals());
        assertTrue(config.enabled);
    }

    function test_AddTokens_OnlyOwner() public {
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](0);

        vm.expectRevert();
        vm.prank(user);
        feeManager.addTokens(tokenConfigs);
    }

    function test_AddTokens_TokenAlreadySupported_Reverts() public {
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)), // Already supported
            decimals: token.decimals(),
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        vm.expectRevert(IFeeManager.TokenAlreadySupported.selector);
        vm.prank(owner);
        feeManager.addTokens(tokenConfigs);
    }

    function test_SetTokenEnabled_Success() public {
        assertTrue(feeManager.isTokenEnabled(address(token)));

        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenEnabledUpdated(address(token), false);

        vm.prank(owner);
        feeManager.setTokenEnabled(address(token), false);

        assertFalse(feeManager.isTokenEnabled(address(token)));

        // Re-enable
        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenEnabledUpdated(address(token), true);

        vm.prank(owner);
        feeManager.setTokenEnabled(address(token), true);

        assertTrue(feeManager.isTokenEnabled(address(token)));
    }

    function test_SetTokenEnabled_TokenNotSupported_Reverts() public {
        TestERC20 unsupportedToken = new TestERC20(18);

        vm.expectRevert(IFeeManager.TokenNotSupported.selector);
        vm.prank(owner);
        feeManager.setTokenEnabled(address(unsupportedToken), false);
    }

    function test_WithdrawToken_Success() public {
        uint256 withdrawAmount = 100 * 10 ** 18;
        uint256 initialBalance = token.balanceOf(address(feeManager));
        uint256 initialRecipientBalance = token.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit IFeeManager.FeesWithdrawn(recipient, address(token), withdrawAmount);

        vm.prank(owner);
        feeManager.withdrawToken(address(token), recipient, withdrawAmount);

        assertEq(token.balanceOf(address(feeManager)), initialBalance - withdrawAmount);
        assertEq(token.balanceOf(recipient), initialRecipientBalance + withdrawAmount);
    }

    function test_WithdrawToken_NativeToken_Success() public {
        uint256 withdrawAmount = 1 ether;

        // Fund the FeeManager with native tokens
        vm.deal(address(feeManager), withdrawAmount);

        uint256 initialFeeManagerBalance = address(feeManager).balance;
        uint256 initialRecipientBalance = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit IFeeManager.FeesWithdrawn(recipient, address(0), withdrawAmount);

        vm.prank(owner);
        feeManager.withdrawToken(address(0), recipient, withdrawAmount);

        assertEq(address(feeManager).balance, initialFeeManagerBalance - withdrawAmount);
        assertEq(recipient.balance, initialRecipientBalance + withdrawAmount);
    }

    function test_WithdrawToken_NativeToken_FailedTransfer_Reverts() public {
        uint256 withdrawAmount = 1 ether;

        // Fund the FeeManager with native tokens
        vm.deal(address(feeManager), withdrawAmount);

        // Create a contract that rejects ETH transfers
        RejectingContract rejectingContract = new RejectingContract();

        vm.expectRevert(IFeeManager.FailedToTransferNative.selector);
        vm.prank(owner);
        feeManager.withdrawToken(address(0), address(rejectingContract), withdrawAmount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTION TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_IsTokenEnabled() public {
        assertTrue(feeManager.isTokenEnabled(address(token)));
        assertTrue(feeManager.isTokenEnabled(address(secondToken)));

        TestERC20 unsupportedToken = new TestERC20(18);
        assertFalse(feeManager.isTokenEnabled(address(unsupportedToken)));
    }

    function test_SupportedTokens() public view {
        IFeeManager.TokenConfig memory config = feeManager.supportedTokens(address(token));
        assertEq(address(config.token), address(token));
        assertEq(config.decimals, token.decimals());
        assertTrue(config.enabled);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   SET TOKEN CONFIG TESTS                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_SetTokenConfig_Success() public {
        // Create new config
        IFeeManager.TokenConfig memory newConfig = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)),
            decimals: token.decimals(),
            enabled: false, // Disable the token
            minFeeCost: 2000, // Change min fee
            maxFeeCost: 200_000 // Change max fee
        });

        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenConfigUpdated(address(token), newConfig);

        vm.prank(owner);
        feeManager.setTokenConfig(address(token), newConfig);

        // Verify the config was updated
        IFeeManager.TokenConfig memory updatedConfig = feeManager.supportedTokens(address(token));
        assertEq(address(updatedConfig.token), address(token));
        assertEq(updatedConfig.decimals, token.decimals());
        assertFalse(updatedConfig.enabled); // Should be disabled now
        assertEq(updatedConfig.minFeeCost, 2000);
        assertEq(updatedConfig.maxFeeCost, 200_000);
    }

    function test_SetTokenConfig_TokenNotSupported_Reverts() public {
        TestERC20 unsupportedToken = new TestERC20(18);

        IFeeManager.TokenConfig memory config = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(unsupportedToken)),
            decimals: unsupportedToken.decimals(),
            enabled: true,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        vm.expectRevert(IFeeManager.TokenNotSupported.selector);
        vm.prank(owner);
        feeManager.setTokenConfig(address(unsupportedToken), config);
    }

    function test_SetTokenConfig_OnlyOwner() public {
        IFeeManager.TokenConfig memory newConfig = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)),
            decimals: token.decimals(),
            enabled: false,
            minFeeCost: 2000,
            maxFeeCost: 200_000
        });

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user); // Non-owner trying to call
        feeManager.setTokenConfig(address(token), newConfig);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   DISABLED TOKEN TESTS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_DisabledToken_SetTokenEnabled_Success() public {
        // Initially enabled
        assertTrue(feeManager.isTokenEnabled(address(token)));

        // Disable the token using setTokenEnabled
        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenEnabledUpdated(address(token), false);

        vm.prank(owner);
        feeManager.setTokenEnabled(address(token), false);

        // Should now return false
        assertFalse(feeManager.isTokenEnabled(address(token)));

        // Re-enable the token
        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenEnabledUpdated(address(token), true);

        vm.prank(owner);
        feeManager.setTokenEnabled(address(token), true);

        // Should now return true again
        assertTrue(feeManager.isTokenEnabled(address(token)));
    }

    function test_DisabledToken_IsTokenEnabled_ReturnsFalse() public {
        // Initially enabled
        assertTrue(feeManager.isTokenEnabled(address(token)));

        // Disable the token
        IFeeManager.TokenConfig memory disabledConfig = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)),
            decimals: token.decimals(),
            enabled: false,
            minFeeCost: 1000,
            maxFeeCost: 100_000
        });

        vm.prank(owner);
        feeManager.setTokenConfig(address(token), disabledConfig);

        // Should now return false
        assertFalse(feeManager.isTokenEnabled(address(token)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   REMOVE TOKEN TESTS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function test_RemoveToken_Success() public {
        // Verify token is initially supported
        IFeeManager.TokenConfig memory initialConfig = feeManager.supportedTokens(address(token));
        assertEq(address(initialConfig.token), address(token));
        assertTrue(feeManager.isTokenEnabled(address(token)));

        // Expect TokenRemoved event
        vm.expectEmit(true, false, false, true);
        emit IFeeManager.TokenRemoved(address(token));

        // Remove the token
        vm.prank(owner);
        feeManager.removeToken(address(token));

        // Verify token is no longer supported
        IFeeManager.TokenConfig memory removedConfig = feeManager.supportedTokens(address(token));
        assertEq(address(removedConfig.token), address(0));
        assertEq(removedConfig.decimals, 0);
        assertFalse(removedConfig.enabled);
        assertEq(removedConfig.minFeeCost, 0);
        assertEq(removedConfig.maxFeeCost, 0);

        // Verify isTokenEnabled returns false for removed token
        assertFalse(feeManager.isTokenEnabled(address(token)));
    }

    function test_RemoveToken_TokenNotSupported_Reverts() public {
        TestERC20 unsupportedToken = new TestERC20(18);

        // Try to remove a token that was never added
        vm.expectRevert(IFeeManager.TokenNotSupported.selector);
        vm.prank(owner);
        feeManager.removeToken(address(unsupportedToken));
    }

    function test_RemoveToken_AlreadyRemovedToken_Reverts() public {
        // First remove the token
        vm.prank(owner);
        feeManager.removeToken(address(token));

        // Try to remove the same token again
        vm.expectRevert(IFeeManager.TokenNotSupported.selector);
        vm.prank(owner);
        feeManager.removeToken(address(token));
    }

    function test_RemoveToken_OnlyOwner() public {
        // Try to remove token as non-owner
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        feeManager.removeToken(address(token));

        // Verify token is still supported
        IFeeManager.TokenConfig memory config = feeManager.supportedTokens(address(token));
        assertEq(address(config.token), address(token));
        assertTrue(feeManager.isTokenEnabled(address(token)));
    }

    function test_RemoveToken_VerifyStorageCleared() public {
        // Get initial config to verify it exists
        IFeeManager.TokenConfig memory initialConfig = feeManager.supportedTokens(address(token));
        assertEq(address(initialConfig.token), address(token));
        assertEq(initialConfig.decimals, token.decimals());
        assertTrue(initialConfig.enabled);
        assertEq(initialConfig.minFeeCost, 1000);
        assertEq(initialConfig.maxFeeCost, 100_000);

        // Remove the token
        vm.prank(owner);
        feeManager.removeToken(address(token));

        // Verify all storage slots are cleared (default values)
        IFeeManager.TokenConfig memory clearedConfig = feeManager.supportedTokens(address(token));
        assertEq(address(clearedConfig.token), address(0));
        assertEq(clearedConfig.decimals, 0);
        assertFalse(clearedConfig.enabled);
        assertEq(clearedConfig.minFeeCost, 0);
        assertEq(clearedConfig.maxFeeCost, 0);
    }

    function test_RemoveToken_CanReAddAfterRemoval() public {
        // Remove the token
        vm.prank(owner);
        feeManager.removeToken(address(token));

        // Verify token is removed
        assertFalse(feeManager.isTokenEnabled(address(token)));

        // Re-add the token with new configuration
        IFeeManager.TokenConfig[] memory tokenConfigs = new IFeeManager.TokenConfig[](1);
        tokenConfigs[0] = IFeeManager.TokenConfig({
            token: IERC20Metadata(address(token)),
            decimals: token.decimals(),
            enabled: true,
            minFeeCost: 2000, // Different min fee
            maxFeeCost: 200_000 // Different max fee
        });

        vm.expectEmit(true, false, true, true);
        emit IFeeManager.TokenAdded(address(token), token.decimals());

        vm.prank(owner);
        feeManager.addTokens(tokenConfigs);

        // Verify token is supported again with new config
        IFeeManager.TokenConfig memory newConfig = feeManager.supportedTokens(address(token));
        assertEq(address(newConfig.token), address(token));
        assertTrue(newConfig.enabled);
        assertEq(newConfig.minFeeCost, 2000);
        assertEq(newConfig.maxFeeCost, 200_000);
        assertTrue(feeManager.isTokenEnabled(address(token)));
    }
}

/// @dev Helper contract that rejects ETH transfers to test failed native token withdrawal
contract RejectingContract {
    // This contract has no receive() or fallback() function, so it will reject ETH transfers

    }
