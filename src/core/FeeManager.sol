// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IFeeManager } from "../interfaces/IFeeManager.sol";

/**
 * @title FeeManager
 * @notice Centralized fee management contract for handling supported tokens and fee withdrawals.
 *
 * @dev
 * The FeeManager maintains configurations for tokens accepted as fee payments by smart accounts.
 * It provides administrative functions to register, enable, disable, and remove supported tokens.
 * It also allows the owner to withdraw collected fees in either ERC-20 tokens or native currency.
 *
 * Key features:
 * - Adds and manages supported fee tokens with validation checks.
 * - Enables or disables specific tokens for fee usage.
 * - Allows configuration updates per token (e.g., decimals, rate settings).
 * - Supports secure withdrawals using SafeERC20.
 *
 * @author Permutize
 * License GNU General Public License v3.0 or later
 *
 * @notice
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
contract FeeManager is IFeeManager, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @dev The supported tokens and their configurations.
    mapping(address => TokenConfig) private _supportedTokens;

    constructor(address _owner) Ownable(_owner) { }

    /// @notice Returns the configuration of a supported token.
    /// @param token The address of the token to query.
    /// @return config The configuration of the token.
    function supportedTokens(address token) external view returns (TokenConfig memory config) {
        return _supportedTokens[token];
    }

    /// @notice Checks whether a token is enabled.
    /// @param token The address of the token to check.
    /// @return enabled The flag indicating whether the token is enabled.
    function isTokenEnabled(address token) public view returns (bool enabled) {
        return _supportedTokens[token].enabled;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ADMIN FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Adds new supported tokens to the paymaster.
    /// @param tokens The supported tokens and their configurations.
    function addTokens(TokenConfig[] calldata tokens) public onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length;) {
            address tokenAddr = address(tokens[i].token);

            // Validate token address
            if (tokenAddr == address(0)) {
                revert InvalidTokenAddress();
            }

            // Check if token is already supported
            if (address(_supportedTokens[tokenAddr].token) != address(0)) {
                revert TokenAlreadySupported();
            }

            // Validate token decimals (prevent overflow in calculations)
            if (tokens[i].decimals > 77) {
                revert TokenDecimalsTooHigh();
            }

            _supportedTokens[tokenAddr] = tokens[i];
            emit TokenAdded(tokenAddr, tokens[i].decimals);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Enables or disables a supported token.
    /// @param token The address of the token to enable or disable.
    /// @param enabled The flag indicating whether the token should be enabled or disabled.
    function setTokenEnabled(address token, bool enabled) external onlyOwner {
        if (address(_supportedTokens[token].token) == address(0)) {
            revert TokenNotSupported();
        }
        _supportedTokens[token].enabled = enabled;
        emit TokenEnabledUpdated(token, enabled);
    }

    /// @notice Modifiy token config
    /// @param token The address of the token to modify.
    /// @param config The new configuration of the token.
    function setTokenConfig(address token, TokenConfig calldata config) external onlyOwner {
        if (address(_supportedTokens[token].token) == address(0)) {
            revert TokenNotSupported();
        }
        _supportedTokens[token] = config;
        emit TokenConfigUpdated(token, config);
    }

    /// @notice Remove supported token
    /// @param token The address of the token to remove.
    function removeToken(address token) external onlyOwner {
        if (address(_supportedTokens[token].token) == address(0)) {
            revert TokenNotSupported();
        }
        delete _supportedTokens[token];
        emit TokenRemoved(token);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = to.call{ value: amount }("");
            if (!success) {
                revert FailedToTransferNative();
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit FeesWithdrawn(to, token, amount);
    }
}
