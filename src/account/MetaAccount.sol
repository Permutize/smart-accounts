// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { BaseAccount } from "../core/BaseAccount.sol";
import { IFeeManager } from "../interfaces/IFeeManager.sol";
import { CallHash } from "../libraries/CallHash.sol";

/**
 * @title MetaAccount
 * @notice A fee-enabled smart account that extends BaseAccount with automatic fee collection.
 *
 * @dev This contract implements a meta-transaction account that requires the first call in every batch
 * to be a valid fee payment to the configured FeeManager. This ensures that relayers can collect
 * fees for executing transactions on behalf of users.
 *
 * Key features:
 * - Inherits all BaseAccount functionality (EIP-712 signing, batch execution, nonce management)
 * - Enforces fee payment as the first call in every batch
 * - Validates fee tokens through the FeeManager
 * - Supports ERC-20 token fee payments
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
contract MetaAccount is BaseAccount {
    using CallHash for Batch;
    /// @notice The fee manager contract that handles fee validation and collection
    /// @dev Immutable to prevent fee manager changes after deployment for security

    IFeeManager public immutable FEE_MANAGER;

    /// @notice Thrown when the provided fee manager address is zero or invalid
    error InvalidFeeManager();

    /// @notice Thrown when the first call in a batch is not a valid fee payment
    /// @dev This error is thrown when:
    /// - The target token is not enabled in the FeeManager
    /// - The call is not an ERC-20 transfer to the FeeManager
    /// - The transfer amount is outside the min/max fee range configured in FeeManager
    /// - The calldata format is invalid (see _isValidFeeCall for expected format)
    ///
    /// Expected fee call format:
    /// - target: enabled ERC-20 token address (registered in FeeManager)
    /// - value: 0 (no ETH sent)
    /// - data: abi.encodeWithSelector(IERC20.transfer.selector, address(FEE_MANAGER), feeAmount)
    ///   where minFeeCost <= feeAmount <= maxFeeCost for the token
    error InvalidFeeCall();

    /**
     * @notice Initializes the MetaAccount with an owner and fee manager
     * @dev Sets up the BaseAccount with EIP-712 domain ("MetaAccount", "1") and configures fee collection
     *
     * @param _owner The initial owner address that can sign transactions for this account
     * @param _feeManager The address of the deployed FeeManager contract for fee validation and collection
     *
     * Requirements:
     * - `_feeManager` must not be the zero address
     * - `_owner` is validated by the BaseAccount constructor
     *
     * @custom:security The fee manager is immutable after deployment to prevent fee bypass attacks
     */
    constructor(
        address _owner,
        address _nonceManager,
        address _feeManager
    )
        BaseAccount("MetaAccount", "1", _owner, _nonceManager)
    {
        if (_feeManager == address(0)) {
            revert InvalidFeeManager();
        }
        FEE_MANAGER = IFeeManager(_feeManager);
    }

    /**
     * @notice Validates a batch of calls before execution, ensuring proper fee payment
     * @dev Overrides BaseAccount's validation to enforce fee payment as the first call
     *
     * This function is called automatically by BaseAccount.execute() before any calls are executed.
     * It ensures that the first call in the batch is a valid fee payment to the FeeManager.
     *
     * @param batch The batch of calls to validate, containing nonce, deadline, and calls array
     *
     * Requirements:
     * - The first call must be a valid fee payment (validated by _isValidFeeCall)
     * - The batch must contain at least one call (enforced by BaseAccount)
     *
     * Reverts:
     * - `InvalidFeeCall()` if the first call is not a valid fee payment
     *
     * @custom:security This validation prevents fee bypass by ensuring every batch pays fees
     */
    function _validateExecute(Batch calldata batch) internal view override {
        // Call parent validation first
        super._validateExecute(batch);

        // Ensure the first call is a valid fee payment for meta-transactions
        bool isValid = _isValidFeeCall(batch.calls[0]);
        if (!isValid) {
            revert InvalidFeeCall();
        }
    }

    /**
     * @notice Validates whether a call represents a proper fee payment
     * @dev Checks if the call is an ERC-20 transfer to the FeeManager with an enabled token
     *
     * This function performs three key validations:
     * 1. The target address is an enabled token in the FeeManager
     * 2. The call data represents an ERC-20 transfer function call
     * 3. The transfer is directed to the FeeManager address
     *
     * @param call The call to validate, containing target address, value, and call data
     * @return bool True if the call is a valid fee payment, false otherwise
     *
     * Call data format expected:
     * - First 4 bytes: IERC20.transfer.selector (0xa9059cbb)
     * - Next 32 bytes: recipient address (must be FeeManager)
     * - Next 32 bytes: transfer amount (must be within min/max fee range)
     *
     * @custom:security Only standard ERC-20 tokens should be enabled in FeeManager.
     * Fee-on-transfer tokens MUST NOT be added to the allowlist as they would result
     * in the FeeManager receiving less than the validated amount, enabling fee bypass.
     */
    function _isValidFeeCall(Call calldata call) internal view returns (bool) {
        IFeeManager.TokenConfig memory tokenInfo = FEE_MANAGER.supportedTokens(call.to);
        if (!tokenInfo.enabled) {
            return false;
        }
        if (call.data.length < 68) {
            // 4 bytes selector + 32 bytes recipient + 32 bytes amount
            return false;
        }

        bytes4 selector = bytes4(call.data[0:4]);
        address to = address(uint160(uint256(bytes32(call.data[4:36]))));
        uint256 amount = uint256(bytes32(call.data[36:68]));
        return selector == IERC20.transfer.selector && to == address(FEE_MANAGER) && amount >= tokenInfo.minFeeCost
            && amount <= tokenInfo.maxFeeCost;
    }
}
