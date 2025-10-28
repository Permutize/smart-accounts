// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

/// @title IIncrementalNonces
/// @notice Interface for a contract that tracks and manages per-address nonces for replay protection.
/// @dev Provides methods for querying and consuming nonces in incremental (monotonic) fashion.
interface IIncrementalNonces {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidNonce(uint256 currentNonce);

    /**
     * @dev Returns the next unused nonce for an address.
     */
    function nonce(address owner) external view returns (uint256);

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function useNonce() external returns (uint256);

    /**
     * @dev Consumes a nonce for a specific address.
     *
     * Returns the current value and increments nonce.
     */
    function useNonce(address owner) external returns (uint256);

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function useCheckedNonce(uint256 checkedNonce) external;

    /**
     * @dev Same as {_useCheckedNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function useCheckedNonce(address owner, uint256 checkedNonce) external;
}
