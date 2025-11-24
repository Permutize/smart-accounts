// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025 Permutize
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/interfaces/IERC1155Receiver.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC1155Holder } from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { IBaseAccount } from "../interfaces/IBaseAccount.sol";
import { CallHash } from "../libraries/CallHash.sol";
import { IIncrementalNonces } from "../interfaces/IIncrementalNonces.sol";

/**
 * @title BaseAccount
 * @notice Core EIP-7702–compatible smart account with batched call execution and EIP-712 signature verification.
 *
 * @dev
 * This contract provides foundational logic for accounts supporting:
 * - Batched transaction execution
 * - Off-chain signature authorization (EIP-712)
 * - Replay protection via a domain separator and call hashing
 *
 * Key features:
 * - Defines an EIP-712 domain separator (name, version, chainId, verifyingContract) to prevent cross-chain replay
 * attacks.
 * - Aggregates multiple calls into a single `callsHash` for signing.
 * - Provides both `execute` (direct) and `executeSigned` (meta-transaction) entry points.
 *
 * @notice
 * The contract assumes that meta-transaction batches are signed by an external EOA (`owner`),
 * which authorizes execution of each batch.
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
contract BaseAccount is
    IBaseAccount,
    IERC165,
    IERC1271,
    ERC1155Holder,
    ERC721Holder,
    EIP712,
    ReentrancyGuard,
    Ownable2Step
{
    using SafeERC20 for IERC20;
    using CallHash for Batch;

    /// @notice Constant for default reverted reason.
    string constant DEFAULT_REVERT_REASON = "BaseAccount: call reverted";

    /// @notice Nonce manager contract.
    IIncrementalNonces public immutable NONCE_MANAGER;

    constructor(
        string memory name,
        string memory version,
        address _owner,
        address _nonceManager
    )
        EIP712(name, version)
        Ownable(_owner)
    {
        NONCE_MANAGER = IIncrementalNonces(_nonceManager);
    }

    /// @notice Modifier to restrict function call to the account itself.
    modifier onlyProxy() {
        _onlyProxy();
        _;
    }

    /// @notice Deadline must be in the future.
    modifier validateDeadline(uint256 deadline) {
        _validateDeadline(deadline);
        _;
    }

    /// @notice Modifier to validate a batch of calls.
    modifier validateCalls(Call[] calldata calls) {
        _validateCalls(calls);
        _;
    }

    /**
     * @notice Validates a single call.
     * @dev Derived contracts should override this to add custom validation logic.
     */
    function _validateExecute(Call[] calldata calls) internal view virtual { }

    /**
     * @notice Validates a batch of calls.
     * @dev Derived contracts should override this to add custom validation logic.
     */
    function _validateExecute(Batch calldata batch) internal view virtual { }

    /**
     * @notice Returns the current nonce for an owner.
     * @param owner The address of the owner.
     * @return The current nonce.
     */
    function nonce(address owner) external view returns (uint256) {
        return NONCE_MANAGER.nonce(owner);
    }

    /**
     * @notice getBatchHash
     * @dev Returns the hash of a batch of calls.
     */
    function getBatchHash(Batch calldata batch) external pure returns (bytes32) {
        return batch.hash();
    }

    /**
     * @notice Execute a batch directly (must be called by the account itself).
     * @dev Direct execution path, used when this smart account initiates its own txs.
     */
    function execute(Call[] calldata calls) external virtual validateCalls(calls) onlyProxy nonReentrant {
        _validateExecute(calls);
        _executeBatch(calls);
    }

    /**
     * @notice Execute a signed batch (EIP-712 meta-tx).
     * @param batch batched calls (the first call can be reserved for fee settlement by MetaAccount)
     * @param signature EIP-712 signature produced by `owner`
     */
    function execute(
        Batch calldata batch,
        bytes calldata signature
    )
        external
        virtual
        validateDeadline(batch.deadline)
        validateCalls(batch.calls)
        nonReentrant
    {
        _validateExecute(batch);
        _useCheckedNonce(batch.nonce);

        bytes32 batchHash = _getBatchTypedHash(batch);
        if (!_checkSignature(batchHash, signature)) {
            revert InvalidSignature();
        }

        // Derived contracts should guard nonce usage (mark used) before calling this.
        _executeBatch(batch.calls);

        // // Emit BatchExecuted with minimal info
        emit BatchExecuted(batch.nonce, batchHash);
    }

    /**
     * @notice simulateBatch
     * @dev Simulates a batch of calls without executing them.
     * @param batch batched calls (the first call can be reserved for fee settlement by MetaAccount)
     * @param signature EIP-712 signature produced by `owner`
     *
     */
    function simulateBatch(
        Batch calldata batch,
        bytes calldata signature
    )
        external
        validateDeadline(batch.deadline)
        validateCalls(batch.calls)
        nonReentrant
    {
        if (tx.origin != address(0)) {
            revert SimulationOnly();
        }

        _validateExecute(batch);

        try NONCE_MANAGER.useCheckedNonce(batch.nonce) { } catch { }

        bytes32 batchHash = _getBatchTypedHash(batch);
        if (!_checkSignature(batchHash, signature)) { }

        _simulateBatch(batch.calls);
        emit BatchExecuted(batch.nonce, batchHash);
    }

    /// @notice Allows the contract owner to withdraw a specified amount of tokens from the contract.
    /// @param to The address to transfer the tokens to.
    /// @param amount The amount of tokens to transfer.
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = to.call{ value: amount }("");
            if (!success) {
                revert FailedToTransfer(to, amount);
            }
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Withdrawn(to, token, amount);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) public view returns (bytes4 magicValue) {
        return _checkSignature(hash, signature) ? this.isValidSignature.selector : bytes4(0xffffffff);
    }

    function supportsInterface(bytes4 id) public pure override(ERC1155Holder, IERC165) returns (bool) {
        return id == type(IERC165).interfaceId || id == type(IBaseAccount).interfaceId
            || id == type(IERC1271).interfaceId || id == type(IERC1155Receiver).interfaceId
            || id == type(IERC721Receiver).interfaceId;
    }

    function _onlyProxy() internal view {
        if (msg.sender != address(this)) {
            revert UnauthorizedCaller(msg.sender);
        }
    }

    function _validateCalls(Call[] calldata calls) internal pure virtual {
        if (calls.length == 0) {
            revert EmptyBatch();
        }
    }

    function _validateDeadline(uint256 deadline) internal view virtual {
        if (deadline <= block.timestamp) {
            revert InvalidDeadline();
        }
    }

    function _simulateBatch(Call[] calldata calls) internal virtual {
        uint256 callCount = calls.length;
        for (uint256 i = 0; i < callCount; i++) {
            (bool success,) = calls[i].to.call{ value: calls[i].value }(calls[i].data);
            success;
        }
    }

    /**
     * @dev Internal: executes each call in order; reverts if any call fails (atomic).
     */
    function _executeBatch(Call[] calldata calls) internal virtual {
        uint256 callCount = calls.length;
        for (uint256 i = 0; i < callCount; i++) {
            _executeCall(calls[i]);
        }
    }

    function _executeCall(Call calldata callItem) internal virtual {
        (bool success, bytes memory returndata) = callItem.to.call{ value: callItem.value }(callItem.data);
        // require(success, _extractRevertReason(returndata));
        if (!success) {
            _extractRevertReason(returndata);
        }
    }

    /**
     * @notice Uses the nonce for the current transaction if it matches the expected nonce.
     * @dev Derived contracts should call this before executing a batch.
     * @param _nonce The expected nonce.
     */
    function _useCheckedNonce(uint256 _nonce) internal {
        NONCE_MANAGER.useCheckedNonce(_nonce);
    }

    // helper to bubble up revert reasons (if available)
    function _extractRevertReason(bytes memory returnData) internal pure {
        if (returnData.length < 68) revert CallReverted(DEFAULT_REVERT_REASON);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // slice the sighash
            returnData := add(returnData, 0x04)
        }
        revert CallReverted(abi.decode(returnData, (string)));
    }

    /**
     * @notice _getBatchTypedHash
     * @dev Returns the hash of a batch of calls.
     */
    function _getBatchTypedHash(Batch calldata batch) internal view returns (bytes32) {
        return _hashTypedDataV4(batch.hash());
    }

    function _checkSignature(bytes32 hash, bytes memory signature) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == address(this);
    }

    receive() external payable { }
    fallback() external payable { }
}
