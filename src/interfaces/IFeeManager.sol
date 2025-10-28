// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IFeeManager
/// @notice Interface defining the structure and behavior of a fee manager used by smart accounts.
/// @dev Provides the required functions and events for managing supported fee tokens.
interface IFeeManager {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           STRUCTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct TokenConfig {
        /// @dev The ERC20 token used for transaction fee payments.
        IERC20Metadata token;
        /// @dev The number of decimals used by the ERC20 token.
        uint8 decimals;
        /// @dev The flag indicating whether the token is enabled.
        bool enabled;
        /// @dev The minimum fee cost in the token's smallest unit (e.g., wei for ETH).
        uint256 minFeeCost;
        /// @dev The maximum fee cost in the token's smallest unit (e.g., wei for ETH).
        uint256 maxFeeCost;
    }

    /// @dev The token is not supported.
    error TokenNotSupported();

    /// @dev The token is already supported.
    error TokenAlreadySupported();

    /// @dev Invalid token address (zero address).
    error InvalidTokenAddress();

    /// @dev Token decimals exceed maximum safe value.
    error TokenDecimalsTooHigh();

    /// @dev The token is not enabled.
    error TokenNotEnabled();

    /// @dev Failed to transfer native asset (ETH, Matic, Avax, etc.).
    error FailedToTransferNative();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Emitted when a new token is added as a supported token.
    event TokenAdded(address indexed token, uint8 decimals);

    /// @dev Emitted when a supported token is removed.
    event TokenRemoved(address indexed token);

    /// @dev Emitted when the enabled status of a supported token is updated.
    event TokenEnabledUpdated(address indexed token, bool enabled);

    /// @dev Emitted when the configuration of a supported token is updated.
    event TokenConfigUpdated(address indexed token, TokenConfig config);

    /// @dev Emitted when withdraw fees from the contract.
    event FeesWithdrawn(address indexed to, address indexed token, uint256 amount);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      STATE VARIABLES                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev The supported tokens and their configurations.
    function supportedTokens(address token) external view returns (TokenConfig memory);

    /// @notice Checks whether a token is enabled.
    /// @param token The address of the token to check.
    /// @return enabled The flag indicating whether the token is enabled.
    function isTokenEnabled(address token) external view returns (bool enabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @notice Adds new supported tokens to the paymaster.
    /// @param tokens The supported tokens and their configurations.
    function addTokens(TokenConfig[] calldata tokens) external;

    /// @notice Enables or disables a supported token.
    /// @param token The address of the token to enable or disable.
    /// @param enabled The flag indicating whether the token should be enabled or disabled.
    function setTokenEnabled(address token, bool enabled) external;

    /// @notice Modifiy token config
    /// @param token The address of the token to modify.
    /// @param config The new configuration of the token.
    function setTokenConfig(address token, TokenConfig calldata config) external;

    /// @notice Remove supported token
    /// @param token The address of the token to remove.
    function removeToken(address token) external;

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param token The address of the token to withdraw.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address token, address to, uint256 amount) external;
}
