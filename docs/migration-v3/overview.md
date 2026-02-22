# Migration Guide — Credential Registry v3 (Redeployment)

This guide covers breaking changes between the previous deployment (`0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe`) and the current deployment (`0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db`). All consuming apps must update.

## Deployed Contracts

Contract addresses are identical on both chains (same deployer, same nonce).

**Previous deployment (v2):**

| Contract | Address |
|---|---|
| CredentialRegistry | `0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe` |
| DefaultScorer | `0x6a0b5ba649C7667A0C4Cd7FE8a83484AEE6C5345` |
| ScorerFactory | `0x05321FAAD6315a04d5024Ee5b175AB1C62a3fd44` |

**Current deployment (v3):**

| Contract | Address | Chains |
|---|---|---|
| Semaphore | `0x8A1fd199516489B0Fb7153EB5f075cDAC83c693D` | mainnet (8453), Sepolia (84532) |
| CredentialRegistry | `0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db` | mainnet (8453), Sepolia (84532) |
| DefaultScorer | `0x315044578dd9480Dd25427E4a4d94b0fc2Fa4f8c` | mainnet (8453), Sepolia (84532) |
| ScorerFactory | `0xAa03996D720C162Fdff246E1D3CEecc792986750` | mainnet (8453), Sepolia (84532) |

Owner: `0x6F0CDcd334BA91A5E221582665Cce0431aD4Fc0b`
Trusted verifier (Sepolia): `0x3c50f7055D804b51e506Bc1EA7D082cB1548376C`
Trusted verifier (mainnet): `0x9186aA65288bFfa67fB58255AeeaFfc4515535d9`

> **Note:** Semaphore address is unchanged. All other contract addresses have changed.

## Breaking Changes Summary

### 1. Attestation struct — `chainId` field added (CRITICAL)

The `Attestation` struct now includes a `chainId` field at position 2, preventing cross-chain replay attacks:

```diff
  struct Attestation {
      address registry;
+     uint256 chainId;
      uint256 credentialGroupId;
      bytes32 credentialId;
      uint256 appId;
      uint256 semaphoreIdentityCommitment;
      uint256 issuedAt;
  }
```

This changes the ABI encoding of every attestation. All code that constructs or hashes attestations (verifiers, task-manager calldata, widget) must include `chainId`.

### 2. Proof functions — `appId_` added as first parameter (CRITICAL)

All proof-related functions now take `appId_` as the first parameter (before `context_`):

```diff
- function submitProof(uint256 context_, CredentialGroupProof calldata proof) returns (uint256)
+ function submitProof(uint256 appId_, uint256 context_, CredentialProof calldata proof) returns (uint256)

- function submitProofs(uint256 context_, CredentialGroupProof[] calldata proofs) returns (uint256)
+ function submitProofs(uint256 appId_, uint256 context_, CredentialProof[] calldata proofs) returns (uint256)

- function verifyProof(uint256 context_, CredentialGroupProof calldata proof) view returns (bool)
+ function verifyProof(uint256 appId_, uint256 context_, CredentialProof calldata proof) view returns (bool)

- function verifyProofs(uint256 context_, CredentialGroupProof[] calldata proofs) view returns (bool)
+ function verifyProofs(uint256 appId_, uint256 context_, CredentialProof[] calldata proofs) view returns (bool)

- function getScore(uint256 context_, CredentialGroupProof[] calldata proofs) view returns (uint256)
+ function getScore(uint256 appId_, uint256 context_, CredentialProof[] calldata proofs) view returns (uint256)
```

The `appId_` parameter is consumer-controlled (not taken from the proof struct), preventing an attacker from substituting a different app's scorer.

### 3. Proof struct renamed: `CredentialGroupProof` → `CredentialProof`

The proof struct has been renamed and extracted to `contracts/interfaces/Types.sol`:

```diff
- struct CredentialGroupProof {
+ struct CredentialProof {
      uint256 credentialGroupId;
      uint256 appId;
      ISemaphore.SemaphoreProof semaphoreProof;
  }
```

Import path: `import {CredentialProof} from "@bringid/contracts/interfaces/Types.sol";`

### 4. Scope formula includes `appId`

The scope used for Semaphore proof binding now includes `appId`:

```diff
- scope = keccak256(abi.encode(msg.sender, context))
+ scope = keccak256(abi.encode(appId, msg.sender, context))
```

All proof generation must use the updated scope formula. Proofs generated with the old formula will fail validation.

### 5. Custom errors replace string-based require messages

All `"BID::..."` revert strings have been replaced with typed custom errors defined in `contracts/interfaces/Errors.sol`:

| Old (string) | New (custom error) |
|---|---|
| `"BID::not registered"` | `NotRegistered()` |
| `"BID::already registered"` | `AlreadyRegistered()` |
| `"BID::app not active"` | `AppNotActive()` |
| `"BID::attestation expired"` | `AttestationExpired()` |
| `"BID::credential group not active"` | `CredentialGroupInactive()` |
| `"BID::recovery pending"` | `RecoveryPending()` |
| `"BID::not expired"` | `NotYetExpired()` |
| `"BID::group mismatch"` | `GroupMismatch()` |
| `"BID::family mismatch"` | _(removed — family ID immutable)_ |
| `"BID::invalid trusted verifier"` | `InvalidTrustedVerifier()` |

New errors added: `WrongChain()`, `InvalidCommitment()`, `DuplicateCredentialGroup()`, `InvalidScorerContract()`, `ScopeMismatch()`, `FutureAttestation()`, and others. See `Errors.sol` for the full list.

### 6. App admin transfer — two-step process

`setAppAdmin()` has been replaced with a two-step transfer:

```diff
- function setAppAdmin(uint256 appId_, address newAdmin_) external;
+ function transferAppAdmin(uint256 appId_, address newAdmin_) external;
+ function acceptAppAdmin(uint256 appId_) external;
```

New event: `AppAdminTransferInitiated(appId, currentAdmin, newAdmin)` fires on `transferAppAdmin()`. The existing `AppAdminTransferred(appId, oldAdmin, newAdmin)` fires on `acceptAppAdmin()`.

### 7. `setCredentialGroupFamily` removed

The `setCredentialGroupFamily()` function has been removed. Family ID is now immutable after credential group creation. The `CredentialGroupFamilySet` event has also been removed.

### 8. IScorer extends IERC165

The `IScorer` interface now extends `IERC165`:

```diff
- interface IScorer {
+ interface IScorer is IERC165 {
```

`setAppScorer()` now validates that the scorer contract implements `IScorer` via `IERC165.supportsInterface()`. Custom scorer contracts must implement `supportsInterface()` returning `true` for the `IScorer` interface ID.

### 9. New contracts: BringIDGated and SimpleAirdrop

New abstract base contract `BringIDGated` (`contracts/BringIDGated.sol`) for smart contracts that consume BringID proofs. It:
- Validates Semaphore `message` binding to an intended recipient (prevents mempool front-running)
- Enforces app ID matching
- Submits proofs to the registry
- Provides view wrappers (`verifyProof`, `verifyProofs`, `getScore`) scoped to the consumer contract

`SimpleAirdrop` (`contracts/examples/SimpleAirdrop.sol`) is a reference implementation.

Interface: `IBringIDGated` (`contracts/interfaces/IBringIDGated.sol`).

### 10. New functions

| Function | Type | Description |
|---|---|---|
| `submitProof(appId, context, proof)` | write | Single-proof submit (new — v2 only had `submitProofs`) |
| `getAppSemaphoreGroupIds(appId)` | view | All Semaphore group IDs for an app |
| `setDefaultScorer(scorer)` | write | Owner updates default scorer for new apps |
| `setDefaultMerkleTreeDuration(duration)` | write | Owner sets registry-level Merkle tree duration |
| `setAppMerkleTreeDuration(appId, duration)` | write | App admin sets per-app Merkle tree duration |
| `transferAppAdmin(appId, newAdmin)` | write | Initiate two-step admin transfer |
| `acceptAppAdmin(appId)` | write | Complete two-step admin transfer |

### 11. New events

| Event | Description |
|---|---|
| `DefaultMerkleTreeDurationSet(duration)` | Registry-level Merkle tree duration changed |
| `AppMerkleTreeDurationSet(appId, duration)` | Per-app Merkle tree duration changed |
| `DefaultScorerUpdated(oldScorer, newScorer)` | Default scorer contract changed |
| `AppAdminTransferInitiated(appId, currentAdmin, newAdmin)` | Two-step admin transfer started |

### 12. Duplicate credential group protection

`submitProofs()` and `getScore()` now revert with `DuplicateCredentialGroup()` if the same `credentialGroupId` appears more than once in the proofs array. This prevents score inflation by submitting the same credential group multiple times.

### 13. Import paths

All Solidity imports now use `@`-prefixed npm-standard paths:

```diff
- import {ICredentialRegistry} from "src/registry/ICredentialRegistry.sol";
+ import {ICredentialRegistry} from "@bringid/contracts/interfaces/ICredentialRegistry.sol";

- import {IScorer} from "src/registry/IScorer.sol";
+ import {IScorer} from "@bringid/contracts/interfaces/IScorer.sol";
```

## Credential Groups

Unchanged from v2. See [migration-guide-v2.md](../migration-guide-v2.md#credential-groups).

## Quick Migration Checklist

- [ ] Update all contract addresses (CredentialRegistry, DefaultScorer, ScorerFactory)
- [ ] Add `chainId` to all `Attestation` struct construction
- [ ] Add `appId_` as first parameter to all proof function calls (`submitProof`, `submitProofs`, `verifyProof`, `verifyProofs`, `getScore`)
- [ ] Rename `CredentialGroupProof` → `CredentialProof` in type definitions
- [ ] Update scope formula to `keccak256(abi.encode(appId, msg.sender, context))`
- [ ] Update error parsing from `"BID::..."` strings to custom error selectors
- [ ] Replace `setAppAdmin()` with `transferAppAdmin()`/`acceptAppAdmin()` two-step flow
- [ ] Remove any `setCredentialGroupFamily()` calls (family ID is immutable)
- [ ] If using custom scorers: implement `IERC165.supportsInterface()` for `IScorer`
- [ ] Update Solidity import paths to `@bringid/contracts/...`
- [ ] Update event listeners for removed/renamed/new events
- [ ] Ensure proofs arrays don't contain duplicate `credentialGroupId` values
- [ ] Re-register all apps on the new contract and update stored `appId` values
- [ ] Re-register all credentials (existing registrations are on the old contract)
