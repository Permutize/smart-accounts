# Core Contracts Documentation

This document describes the core smart contracts in `src/core/`: `BaseAccount.sol`, `FeeManager.sol`, and `IncrementalNonces.sol`. It covers their purpose, features, key functions, events, errors, security, and usage patterns in the gasless integration.

## BaseAccount.sol

### Overview
- Core EIP-7702–compatible smart account supporting batched call execution and EIP-712 signature verification.
- Provides the foundational execution, signature verification, and replay protection used by `MetaAccount`.

### Key Features
- Batched calls with a single signature.
- EIP-712 domain separation: `name`, `version`, `chainId`, `verifyingContract`.
- Call hashing via `libraries/CallHash.sol` to produce stable typed data for signing.
- Per-owner monotonic nonces via `IncrementalNonces`.
- Two execution paths: direct `execute(Call[])` and signed/meta `execute(Batch, signature)`.
- Simulation entry point `simulateBatch` for off-chain validation.

### Design Decisions
- Uses OpenZeppelin `EIP712`, `ECDSA`, `ReentrancyGuard`, `Ownable`, and token receiver mixins (`ERC1155Holder`, `ERC721Holder`).
- Separates validation hooks: `_validateExecute(Call[] calls)` and `_validateExecute(Batch batch)` are `virtual` for derived contracts (e.g., `MetaAccount`) to enforce policies (such as fee payment as the first call).
- Delegates nonce management to an external `IIncrementalNonces` to simplify replay protection and allow shared nonce semantics.

### Public API
- `function nonce(address owner) external view returns (uint256)`
  - Returns the current nonce for `owner` (next unused value).

- `function getBatchHash(Batch calldata batch) external pure returns (bytes32)`
  - Returns the hash of a batched call set using `CallHash`.

- `function execute(Call[] calldata calls) external validateCalls(calls) onlyProxy nonReentrant`
  - Direct execution of calls by the account itself. Calls `_validateExecute(calls)` then `_executeBatch(calls)`.

- `function execute(Batch calldata batch, bytes calldata signature) external`
  - Signed execution path.
  - Validates deadline and calls, consumes nonce via `_useCheckedNonce(batch.nonce)`, verifies EIP-712 signature, and executes.

- `function simulateBatch(Batch calldata batch, bytes calldata signature) external`
  - Read-only simulation entry point for off-chain or sandbox environments; reverts if `tx.origin != address(0)` to ensure it is not used in production execution.

- `function withdrawToken(address token, address to, uint256 amount) external`
  - Owner-controlled withdrawals of ERC-20 or native asset held by the account.

### Events
- `event BatchExecuted(uint256 indexed nonce, bytes32 indexed callsHash)`
  - Emitted after successful execution or simulation of a batch.

- `event Withdrawn(address indexed to, address indexed token, uint256 amount)`
  - Emitted on token/native withdrawals.

### Errors
- `error EmptyBatch()` – when batch contains no calls.
- `error UnauthorizedCaller(address caller)` – call path not authorized.
- `error InvalidDeadline()` – deadline is not in the future.
- `error CallReverted(string reason)` – a call within batch reverted.
- `error SimulationOnly()` – `simulateBatch` called in non-simulation context.
- `error FailedToTransfer(address to, uint256 amount)` – native transfer failed.
- `error InvalidSignature()` – EIP-712 signature mismatch.

### Security Considerations
- EIP-712 domain separation prevents cross-chain replay.
- Nonce consumption is strictly monotonic via `IncrementalNonces`.
- `nonReentrant` modifiers protect external entry points.
- Validation hooks allow derived contracts to enforce fee payment, policy checks, and safelist/denylist logic.

### Usage Example (Meta-Transaction)
1. Backend forms `Batch` typed data with fields:
   - `nonce`, `deadline`, `calls: Call[]`.
   - Types: `Call { address to, uint256 value, bytes data }`, `Batch { uint256 nonce, uint256 deadline, Call[] calls }`.
2. User signs the EIP-712 `Batch` using their EOA.
3. Relayer submits `execute(batch, signature)` to the account.

### Integration Notes
- `MetaAccount` overrides `_validateExecute(Batch)` to enforce fee payment as the first call.
- Use `getBatchHash(Batch)` to pre-compute and cache batch hashes as part of quote handling.

---

## FeeManager.sol

### Overview
- Centralized fee management for validating supported ERC-20 tokens and handling fee withdrawals.
- Enables administrative control of token configurations used for paying relayer fees.

### Key Features
- Add/enable/disable/remove tokens with validation.
- Token config comprises `token`, `decimals`, `enabled`, `minFeeCost`, `maxFeeCost`.
- Owner can withdraw accumulated fees in native or ERC-20.

### Design Decisions
- Contract is `Ownable`; only owner can mutate token registry or withdraw.
- Uses `SafeERC20` for robust ERC-20 transfers.
- Keeps minimal state (`_supportedTokens`) for simplicity; pricing markup and exchange rates are expected to be determined off-chain (e.g., by backend services).

### Public API
- `function supportedTokens(address token) external view returns (TokenConfig memory)`
  - Returns the stored config for a token address.

- `function isTokenEnabled(address token) public view returns (bool)`
  - Returns whether the token is enabled for fee payment.

- `function addTokens(TokenConfig[] calldata tokens) public onlyOwner`
  - Registers new supported tokens; validates address and decimals, prevents duplicates.

- `function setTokenEnabled(address token, bool enabled) external onlyOwner`
  - Enables/disables a previously supported token.

- `function setTokenConfig(address token, TokenConfig calldata config) external onlyOwner`
  - Updates full token configuration.

- `function removeToken(address token) external onlyOwner`
  - Removes token from the registry.

- `function withdrawToken(address token, address to, uint256 amount) external onlyOwner`
  - Withdraws collected fees in ERC-20 or native asset; emits `FeesWithdrawn`.

### Events
- `event TokenAdded(address indexed token, uint8 decimals)`
- `event TokenRemoved(address indexed token)`
- `event TokenEnabledUpdated(address indexed token, bool enabled)`
- `event TokenConfigUpdated(address indexed token, TokenConfig config)`
- `event FeesWithdrawn(address indexed to, address indexed token, uint256 amount)`

### Errors
- `error TokenNotSupported()` – operations on unknown token.
- `error TokenAlreadySupported()` – duplicate registration.
- `error InvalidTokenAddress()` – zero address.
- `error TokenDecimalsTooHigh()` – decimals exceed safe limit.
- `error TokenNotEnabled()` – token disabled for fee usage.
- `error FailedToTransferNative()` – native asset transfer failed.

### Security Considerations
- Restricted admin surface via `onlyOwner`.
- Validate token addresses and decimals to prevent misconfiguration.
- Fee transfers rely on ERC-20 `transfer`; use `SafeERC20` for safety.

### Usage Pattern with MetaAccount
- Backend quotes include fee amount and target token.
- First call in `Batch` must be an ERC-20 `transfer(FeeManager, amount)` from the smart account to the FeeManager.
- `MetaAccount._isValidFeeCall` checks:
  - Token is enabled in `FeeManager`.
  - Call calldata matches `IERC20.transfer.selector`.
  - Recipient equals `FeeManager`.
  - Amount within `[minFeeCost, maxFeeCost]`.

---

## IncrementalNonces.sol

### Overview
- Per-address monotonic nonce manager for replay protection and transaction sequencing.
- Provides the next unused nonce for a given address (starting at `0`).

### Key Features
- `nonce(owner)` returns next unused nonce.
- `useNonce()` and `useNonce(owner)` consume and return current, then increment.
- Checked consumption APIs `useCheckedNonce(checkedNonce)` and `useCheckedNonce(owner, checkedNonce)` revert if mismatch.

### Public API
- `function nonce(address owner) external view returns (uint256)`

- `function useNonce() external returns (uint256)`

- `function useNonce(address owner) external onlyOwner returns (uint256)`

- `function useCheckedNonce(uint256 checkedNonce) external` – reverts with `InvalidNonce(current)` if mismatch.

- `function useCheckedNonce(address owner, uint256 checkedNonce) external onlyOwner` – reverts with `InvalidNonce(current)` if mismatch.

### Errors
- `error InvalidNonce(uint256 currentNonce)` – provided nonce does not match next unused.

### Security Considerations
- Cross-account operations are owner-only.
- Uses `unchecked` increment for gas-efficiency; practical overflow is unreachable.

### Usage Pattern
- Backend requests `nonce(owner)` to include in EIP-712 batch typed data.
- Account consumes the nonce during execution (`BaseAccount.execute`), preventing replay.

---

## Integration Notes and Example

The TypeScript client and backend implement a gasless flow:

1. Client fetches supported tokens via GraphQL: `getGaslessSupportedTokens(chain)`.
2. Client requests a quote: `getGaslessQuote({ chain, userAddress, token, calls })`.
3. Backend responds with `data.eip712` (domain, types, message) and fee info.
4. Client signs EIP-712 batch and EIP-7702 authorization, then calls `executeGasless`.
5. Backend verifies authorization and submits `BaseAccount.execute(batch, signature)` to network.

See `script/example/` for a runnable demo (`index.ts`, `client.ts`, `api.ts`, `types.ts`).