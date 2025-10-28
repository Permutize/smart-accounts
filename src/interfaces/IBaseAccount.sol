// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

/// @title IBaseAccount
/// @notice Interface for the BaseAccount contract, defining core account functions and structure.
/// @dev Serves as the standard interface for EIP-7702-compatible accounts.
interface IBaseAccount {
    /// @notice Struct for a single call in a batch.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    /// @notice Struct for a batch of calls.
    struct Batch {
        uint256 nonce;
        uint256 deadline;
        Call[] calls;
    }

    /// @notice Error thrown when the batch is empty.
    error EmptyBatch();

    /// @notice Error thrown when the account is not authorized to execute a call.
    error UnauthorizedCaller(address caller);

    /// @notice Error thrown when invalid deadline is provided.
    error InvalidDeadline();

    /// @notice Error thrown when a call in a batch reverted.
    error CallReverted(string reason);

    /// @notice Error thrown when the simulator is not zero address.
    error SimulationOnly();

    /// @notice Error thrown when failed to transfer native token.
    error FailedToTransfer(address to, uint256 amount);

    /// @notice Error thrown when the signature is invalid.
    error InvalidSignature();

    /// @notice Event emitted when a batch of calls is executed.
    event BatchExecuted(uint256 indexed nonce, bytes32 indexed callsHash);

    /// @notice Event emitted when fees are withdrawn.
    event Withdrawn(address indexed to, address indexed token, uint256 amount);

    /// @notice Returns the current nonce for an owner.
    /// @param owner The address of the owner.
    /// @return The current nonce.
    function nonce(address owner) external view returns (uint256);

    /// @notice Execute batch of calls (must be called by the account itself).
    function execute(Batch calldata batch, bytes calldata signature) external;

    /// @notice Execute batch directly (must be called by the account itself).
    function execute(Call[] calldata calls) external;

    /// @notice Simulate batch of calls (must be called by the account itself).
    function simulateBatch(Batch calldata batch, bytes calldata signature) external;

    /// @notice Get hash of a batch of calls.
    function getBatchHash(Batch calldata batch) external view returns (bytes32);

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @dev Only the contract owner can call this function.
    /// @param token The address of the token to withdraw.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address token, address to, uint256 amount) external;
}
