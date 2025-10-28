// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { IBaseAccount } from "../interfaces/IBaseAccount.sol";

/**
 * @title CallHash
 * @notice Library for computing deterministic EIP-712-style hashes for batched and individual calls.
 *
 * @dev
 * - Defines `CALL_TYPEHASH` and `BATCH_TYPEHASH` for EIP-712 domain separation.
 * - `hash()` returns the full batch hash including nonce, deadline, and call array.
 * - Each call is encoded and hashed individually for replay protection and signature verification.
 *
 * Used by: {BaseAccount}, {MetaAccount}
 *
 * Design notes:
 * - Internal and pure — does not perform storage reads/writes.
 * - The keccak256 packing of calls ensures uniqueness across arbitrary calldata.
 * - Compatible with EIP-7702-compliant smart accounts.
 */
library CallHash {
    /// @notice Hash of a single call.
    bytes32 public constant CALL_TYPEHASH = keccak256("Call(address to,uint256 value,bytes data)");
    /// @notice Hash of a batch of calls.
    bytes32 public constant BATCH_TYPEHASH =
        keccak256("Batch(uint256 nonce,uint256 deadline,Call[] calls)Call(address to,uint256 value,bytes data)");

    /// @notice Computes the hash of a batch of calls.
    function hash(IBaseAccount.Batch memory batch) internal pure returns (bytes32) {
        bytes32[] memory callHashes = new bytes32[](batch.calls.length);
        uint256 callCount = batch.calls.length;
        for (uint256 i = 0; i < callCount; i++) {
            callHashes[i] = _hashCall(batch.calls[i]);
        }

        return keccak256(
            abi.encode(CallHash.BATCH_TYPEHASH, batch.nonce, batch.deadline, keccak256(abi.encodePacked(callHashes)))
        );
    }

    /// @notice Computes the hash of a single call.
    function _hashCall(IBaseAccount.Call memory call) internal pure returns (bytes32) {
        return keccak256(abi.encode(CallHash.CALL_TYPEHASH, call.to, call.value, keccak256(call.data)));
    }
}
