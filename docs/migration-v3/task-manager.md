# Migration Instructions — BringID Task Manager (v2 → v3)

## Overview

The Task Manager accepts, schedules, and batches verification/claim tasks before sending them to blockchain relayers. It directly constructs calldata for the CredentialRegistry contract.

## Required Changes

### 1. Contract Address

**File:** Environment variables or config files

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62
```

### 2. Attestation Struct — `chainId` Field in Calldata (CRITICAL)

**File:** `src/services/sender-services/` (verification batch sender)

The `Attestation` struct now includes `chainId` at position 2. All calldata encoding for `registerCredential` must include it:

```diff
  const callData = registryInterface.encodeFunctionData('registerCredential', [
-   { registry, credentialGroupId, credentialId, appId, semaphoreIdentityCommitment: commitment, issuedAt },
+   { registry, chainId, credentialGroupId, credentialId, appId, semaphoreIdentityCommitment: commitment, issuedAt },
    signature
  ])
```

The `chainId` value comes from the verifier response (`attestation.chain_id`) and must match the target chain:
- Base Mainnet: `8453`
- Base Sepolia: `84532`

The contract enforces `attestation.chainId == block.chainid` and reverts with `WrongChain()` on mismatch.

### 3. Claim Task Calldata — `appId` as First Parameter (CRITICAL)

**File:** `src/services/sender-services/` (claim batch sender)

If claim tasks construct calldata for `submitProofs`, the function signature has changed — `appId` is now the first parameter:

```diff
  const callData = registryInterface.encodeFunctionData(
    'submitProofs',
-   [context, proofs]
+   [appId, context, proofs]
  )
```

Same applies to `submitProof` (single proof):

```diff
  const callData = registryInterface.encodeFunctionData(
    'submitProof',
-   [context, proof]
+   [appId, context, proof]
  )
```

### 4. Verification Task API — `chain_id` Field Addition

**Files:** `src/controllers/task-controller.ts`, validation schemas, `src/services/task-service.ts`

Add `chain_id` to the verification request:

```diff
  interface IAddVerificationRequest {
    credential_id: string
    registry: string
+   chain_id: string
    credential_group_id: string
    app_id: string
    verifier_signature: string
    identity_commitment: string
+   issued_at: string
  }
```

Update Celebrate/Joi validation schemas accordingly.

### 5. Task Model — Updated Params

**File:** Task MongoDB model/schema

```diff
  interface ITaskParams {
    credentialId?: string
    registry?: string
+   chainId?: string
    credentialGroupId?: string
    appId?: string
    verifierSignature?: string
    identityCommitment?: string
+   issuedAt?: string
  }
```

Update the `_flattenTask` method to map `chainId` → `chain_id` in API responses.

### 6. Contract ABI Update

Update the CredentialRegistry ABI used for encoding calldata:

- `Attestation` struct: add `chainId` (uint256) at position 2
- `submitProof(uint256 appId, uint256 context, CredentialProof)` — new first parameter
- `submitProofs(uint256 appId, uint256 context, CredentialProof[])` — new first parameter

### 7. Contract Error Handling — Custom Errors

**File:** `src/configs/` or error handling utilities

If the task-manager parses contract error messages from relayer responses, update from string matching to custom error decoding:

```diff
- 'BID::not registered' → 'NOT_REGISTERED'
- 'BID::already registered' → 'ALREADY_REGISTERED'
+ NotRegistered() → 'NOT_REGISTERED'
+ AlreadyRegistered() → 'ALREADY_REGISTERED'
```

New errors to handle:
- `WrongChain()` — attestation `chainId` doesn't match target chain
- `DuplicateCredentialGroup()` — same credential group appears twice in proof batch
- `InvalidCommitment()` — zero commitment in attestation
- `AppIdMismatch()` — proof's appId doesn't match the function parameter

### 8. Re-registration

All apps must be re-registered on the new contract via `registerApp()`. Update stored app IDs. Existing registrations from the old contract must be re-done on the new contract.

## No Changes Required

- Batch processing and scheduling logic
- MongoDB connection and general infrastructure
- Drop whitelist configuration
- Cron scheduling
- Winston logging
- Task deduplication logic (field names unchanged from v2)
- Credential group IDs (unchanged from v2)
