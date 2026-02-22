# Migration Instructions — BringID SDK (v2 → v3)

## Overview

The BringID SDK (`bringid` npm package) provides `BringID` class for reputation scoring, humanity verification, and Semaphore proof verification (on-chain via Multicall3 or off-chain via API). Includes a `BringIDModal` React component.

## Required Changes

### 1. Contract Addresses

Update all hardcoded or configured contract addresses:

```diff
- CredentialRegistry: '0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe'
+ CredentialRegistry: '0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db'

- DefaultScorer: '0x6a0b5ba649C7667A0C4Cd7FE8a83484AEE6C5345'
+ DefaultScorer: '0x315044578dd9480Dd25427E4a4d94b0fc2Fa4f8c'

- ScorerFactory: '0x05321FAAD6315a04d5024Ee5b175AB1C62a3fd44'
+ ScorerFactory: '0xAa03996D720C162Fdff246E1D3CEecc792986750'
```

Semaphore address is unchanged: `0x8A1fd199516489B0Fb7153EB5f075cDAC83c693D`.

### 2. Registry ABI — Proof Functions Now Take `appId` First (CRITICAL)

**File:** `src/abi/registry.tsx`

All proof function signatures have changed — `appId` is now the first parameter:

```diff
- 'function submitProof(uint256 context, (uint256 credentialGroupId, uint256 appId, (uint256 merkleTreeDepth, uint256 merkleTreeRoot, uint256 nullifier, uint256 message, uint256 scope, uint256[8] points) semaphoreProof) proof) returns (uint256)'
+ 'function submitProof(uint256 appId, uint256 context, (uint256 credentialGroupId, uint256 appId, (uint256 merkleTreeDepth, uint256 merkleTreeRoot, uint256 nullifier, uint256 message, uint256 scope, uint256[8] points) semaphoreProof) proof) returns (uint256)'

- 'function submitProofs(uint256 context, (uint256 credentialGroupId, uint256 appId, (uint256 merkleTreeDepth, uint256 merkleTreeRoot, uint256 nullifier, uint256 message, uint256 scope, uint256[8] points) semaphoreProof)[] proofs) returns (uint256)'
+ 'function submitProofs(uint256 appId, uint256 context, (uint256 credentialGroupId, uint256 appId, (uint256 merkleTreeDepth, uint256 merkleTreeRoot, uint256 nullifier, uint256 message, uint256 scope, uint256[8] points) semaphoreProof)[] proofs) returns (uint256)'

- 'function verifyProof(uint256 context, (uint256 credentialGroupId, uint256 appId, ...) proof) view returns (bool)'
+ 'function verifyProof(uint256 appId, uint256 context, (uint256 credentialGroupId, uint256 appId, ...) proof) view returns (bool)'

- 'function verifyProofs(uint256 context, (...)[] proofs) view returns (bool)'
+ 'function verifyProofs(uint256 appId, uint256 context, (...)[] proofs) view returns (bool)'

- 'function getScore(uint256 context, (...)[] proofs) view returns (uint256)'
+ 'function getScore(uint256 appId, uint256 context, (...)[] proofs) view returns (uint256)'
```

### 3. On-Chain Proof Verification (Multicall3) — Updated Encoding (CRITICAL)

**File:** `src/modules/bring-id-sdk/index.ts` (verifyProofs method)

Update the Multicall3 call data encoding to include `appId` as first parameter:

```diff
  const callData = registryInterface.encodeFunctionData(
    'verifyProof',
-   [context, { credentialGroupId, appId, semaphoreProof }]
+   [appId, context, { credentialGroupId, appId, semaphoreProof }]
  )
```

Or for batch:
```diff
  const callData = registryInterface.encodeFunctionData(
    'verifyProofs',
-   [context, proofs]
+   [appId, context, proofs]
  )
```

### 4. Attestation Struct — `chainId` Field (CRITICAL)

The `Attestation` struct now includes `chainId` at position 2:

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

If the SDK constructs or validates attestation data, include `chainId` (Base Mainnet: `8453`, Base Sepolia: `84532`).

Update the ABI type definition:

```diff
  const attestationType = '(address registry, uint256 credentialGroupId, bytes32 credentialId, uint256 appId, uint256 semaphoreIdentityCommitment, uint256 issuedAt)'
+ const attestationType = '(address registry, uint256 chainId, uint256 credentialGroupId, bytes32 credentialId, uint256 appId, uint256 semaphoreIdentityCommitment, uint256 issuedAt)'
```

### 5. Verifier Response — `chain_id` Field

If the SDK defines types for verifier responses, add `chain_id`:

```diff
  interface IAttestationResponse {
    attestation: {
      registry: string
+     chain_id: string
      credential_group_id: string
      credential_id: string
      app_id: string
      semaphore_identity_commitment: string
      issued_at: string
    }
    signature: string
  }
```

### 6. Scope Formula Change

The Semaphore proof scope now includes `appId`:

```diff
- scope = keccak256(abi.encode(msg.sender, context))
+ scope = keccak256(abi.encode(appId, msg.sender, context))
```

If the SDK computes or validates scope values client-side, update the formula.

### 7. Error Handling — Custom Errors Replace Strings

If the SDK parses contract revert reasons, update from string matching to custom error selectors:

```diff
- if (revertReason === 'BID::not registered') { ... }
- if (revertReason === 'BID::already registered') { ... }
+ // Decode using custom error selectors from Errors.sol ABI
+ // NotRegistered(): 0x...
+ // AlreadyRegistered(): 0x...
```

### 8. Proof Type Rename

**File:** `src/types/`

Rename the proof type to match the contract:

```diff
- type TCredentialGroupProof = {
+ type TCredentialProof = {
    credential_group_id: string
    app_id: string
    semaphore_proof: { ... }
  }
```

### 9. Re-registration Required

All apps must re-register on the new contract via `registerApp()`. Existing app IDs from the old contract are not valid on the new contract. Store the new `appId` values.

All user credentials must be re-registered. Existing registrations on `0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe` are not accessible from `0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db`.

## No Changes Required

- `getAddressScore()` — address-based scoring is independent of registry changes
- `destroy()` cleanup logic
- Error classes (internal SDK errors, not contract errors)
- Domain whitelist
- General postMessage architecture
- Credential group IDs are unchanged from v2
- Semaphore identity derivation formula is unchanged
