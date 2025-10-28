// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IIncrementalNonces } from "../interfaces/IIncrementalNonces.sol";

/**
 * @title IncrementalNonce
 * @notice Provides per-address monotonic nonces for replay protection and transaction sequencing.
 *
 * @dev
 * This contract maintains a separate nonce counter for each address to ensure that each signed
 * operation or meta-transaction can be executed only once.
 *
 * Key features:
 * - Stores a dedicated nonce for every address in `_nonces`.
 * - Starts each address at nonce `0`, incrementing by `1` on each use.
 * - `nonce(owner)` returns the next unused nonce.
 * - Nonce consumption uses `x++` semantics — returning the current value before incrementing.
 * - Users can consume their own nonce via `useNonce()` or `useCheckedNonce(uint256)`.
 * - The contract owner can check or consume nonces for any address using owner-only functions.
 * - Reverts with `InvalidNonce(current)` if a checked nonce does not match the expected next value.
 *
 * Typical usage:
 * - Include the returned nonce in a signed message or meta-transaction to prevent replays.
 * - Verify that the provided nonce equals `nonce(sender)` before execution, then consume it.
 *
 * Design notes:
 * - Nonces are strictly monotonic — there is no reset or decrement functionality.
 * - Increments use `unchecked` arithmetic for gas efficiency; overflow is practically impossible.
 * - Access control: only the contract owner may operate on nonces for other addresses.
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
contract IncrementalNonces is IIncrementalNonces, Ownable {
    // uint256 private _nonce;
    mapping(address => uint256) private _nonces;

    /// @param initialOwner The address granted ownership for managing others' nonces.
    constructor(address initialOwner) Ownable(initialOwner) { }

    /// @notice Returns the next unused nonce for a given address.
    /// @param owner The address whose next nonce is queried.
    /// @return The next unused nonce for `owner`.
    function nonce(address owner) external view returns (uint256) {
        return _nonces[owner];
    }

    /// @notice Consumes the caller's nonce.
    /// @dev Returns the current nonce value for `msg.sender` and then increments it.
    /// @return The consumed nonce value for the caller.
    function useNonce() external returns (uint256) {
        return _useNonce();
    }

    /// @notice Consumes the nonce for a specific address.
    /// @dev Owner-only. Returns the current nonce value for `owner` and then increments it.
    /// @param owner The address whose nonce will be consumed.
    /// @return The consumed nonce value for `owner`.
    function useNonce(address owner) external onlyOwner returns (uint256) {
        return _useNonce(owner);
    }

    /// @notice Consumes the caller's nonce only if it matches `checkedNonce`.
    /// @dev Reverts with `InvalidNonce(current)` when `checkedNonce` does not equal the next unused nonce.
    /// @param checkedNonce The expected next nonce value for the caller.
    function useCheckedNonce(uint256 checkedNonce) external {
        uint256 current = _useNonce();
        if (checkedNonce != current) {
            revert InvalidNonce(current);
        }
    }

    /// @notice Consumes `owner`'s nonce only if it matches `checkedNonce`.
    /// @dev Owner-only. Reverts with `InvalidNonce(current)` when `checkedNonce` does not equal the next unused nonce.
    /// @param owner The address whose nonce is checked and consumed.
    /// @param checkedNonce The expected next nonce value for `owner`.
    function useCheckedNonce(address owner, uint256 checkedNonce) external onlyOwner {
        uint256 current = _useNonce(owner);
        if (checkedNonce != current) {
            revert InvalidNonce(current);
        }
    }

    /// @dev Internal helper that consumes `owner`'s nonce.
    /// @param owner The address whose nonce will be consumed.
    /// @return The consumed nonce value for `owner`.
    function _useNonce(address owner) internal returns (uint256) {
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[owner]++;
        }
    }

    /// @dev Internal helper that consumes the caller's nonce.
    /// @return The consumed nonce value for `msg.sender`.
    function _useNonce() internal returns (uint256) {
        unchecked {
            // It is important to do x++ and not ++x here.
            return _nonces[msg.sender]++;
        }
    }
}
