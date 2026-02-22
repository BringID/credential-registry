# Migration Instructions — Verify Proofs API (v2 → v3)

## Overview

The Verify Proofs API verifies Semaphore proofs by simulating Multicall3 calls against the CredentialRegistry. It does not execute transactions — only simulates them.

## Required Changes

### 1. Chain Registries — Updated Contract Addresses (CRITICAL)

**File:** `src/configs/chain-registries.ts`

Update the registry whitelist:

```diff
  export const chainRegistries: Record<number, string[]> = {
-   84532: ['0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe'],
-   8453: ['0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe'],
+   84532: ['0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db'],
+   8453: ['0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db'],
  }
```

### 2. Registry ABI — Proof Functions Take `appId` First (CRITICAL)

**File:** ABI definitions used in `src/services/transaction-data-service.ts`

All proof function signatures have changed — `appId` is the first parameter:

```diff
- 'function verifyProof(uint256 context, (uint256 credentialGroupId, uint256 appId, ...) proof) view returns (bool)'
+ 'function verifyProof(uint256 appId, uint256 context, (uint256 credentialGroupId, uint256 appId, ...) proof) view returns (bool)'
```

Update the Multicall3 call data encoding:

```diff
  const callData = registryInterface.encodeFunctionData(
    'verifyProof',
-   [context, { credentialGroupId, appId, semaphoreProof }]
+   [appId, context, { credentialGroupId, appId, semaphoreProof }]
  )
```

Or for batch verification (preferred — single call instead of Multicall3):

```diff
  const callData = registryInterface.encodeFunctionData(
    'verifyProofs',
-   [context, proofs]
+   [appId, context, proofs]
  )
```

### 3. Scope Computation

If the API computes or validates the expected scope before simulation, update the formula:

```diff
- scope = keccak256(abi.encode(msg.sender, context))
+ scope = keccak256(abi.encode(appId, msg.sender, context))
```

### 4. Error Handling — Custom Errors

**File:** Error parsing utilities

If the API parses contract revert reasons from simulation failures, update from string matching to custom error selectors:

```diff
- 'BID::credential group not active'
+ CredentialGroupInactive()

- 'BID::app not active'
+ AppNotActive()
```

New errors that may occur during proof verification:
- `AppIdMismatch()` — proof's `appId` doesn't match the function parameter
- `ScopeMismatch()` — proof scope doesn't match computed scope
- `NoSemaphoreGroup()` — no Semaphore group exists for the (credentialGroupId, appId) pair
- `InvalidProof()` — Semaphore proof verification failed
- `DuplicateCredentialGroup()` — same credentialGroupId appears twice in batch

To decode custom errors:

```typescript
const iface = new ethers.Interface(registryAbi)
const decoded = iface.parseError(revertData)
// decoded.name === 'AppIdMismatch', 'InvalidProof', etc.
```

### 5. Request Validation — `app_id` Required

**File:** `src/utils/celebrate-builder.ts` (Joi schemas)

Ensure `app_id` is validated as required (should already be present from v2 migration, but verify):

```typescript
const proofSchema = Joi.object({
  credential_group_id: Joi.string().required(),
  app_id: Joi.string().required(),
  semaphore_proof: semaphoreProofSchema.required()
})
```

## No Changes Required

- Multicall3 aggregation pattern (same approach, just different calldata)
- Provider caching per chain ID
- General API structure and Express middleware
- Winston logging
- RPC configuration pattern
- Request/response shape for proofs (field names unchanged from v2)
- Proof struct fields (credentialGroupId, appId, semaphoreProof — unchanged)
